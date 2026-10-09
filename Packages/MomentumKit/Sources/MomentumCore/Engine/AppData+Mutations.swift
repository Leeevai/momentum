import Foundation

// MARK: - Goals

extension AppData {
    public func goal(_ id: UUID) -> Goal? {
        goals.first { $0.id == id }
    }

    /// Inserts a new goal or replaces the stored one with the same id.
    public mutating func upsert(_ goal: Goal) {
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[index] = goal
        } else {
            goals.append(goal)
        }
    }

    public mutating func updateGoal(_ id: UUID, _ change: (inout Goal) -> Void) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        change(&goals[index])
    }

    /// Removes a goal with all of its history.
    public mutating func deleteGoal(_ id: UUID) {
        goals.removeAll { $0.id == id }
        entries.removeAll { $0.goalID == id }
        if session?.goalID == id { session = nil }
    }

    /// Copies a goal's settings, links, milestones and books (reset to unread), without history.
    @discardableResult
    public mutating func duplicateGoal(_ id: UUID, at now: Date = .now) -> Goal? {
        guard let original = goal(id), let index = goals.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.name = "\(original.name) copy"
        copy.createdAt = now
        copy.archivedAt = nil
        copy.breaks = []
        copy.milestones = original.milestones.map { Milestone(title: $0.title, dueDate: $0.dueDate) }
        copy.books = original.books.map { Book(title: $0.title, author: $0.author, totalPages: $0.totalPages, link: $0.link, addedAt: now) }
        copy.links = original.links.map { GoalLink(title: $0.title, url: $0.url, bookmark: $0.bookmark, opensWithFocus: $0.opensWithFocus) }
        goals.insert(copy, at: index + 1)
        return copy
    }

    /// Reorders goals the way `List.onMove` reports it.
    public mutating func moveGoals(fromOffsets source: IndexSet, toOffset destination: Int) {
        goals.move(fromOffsets: source, toOffset: destination)
    }

    public mutating func archiveGoal(_ id: UUID, at now: Date = .now) {
        if session?.goalID == id { stopFocus(at: now) }
        updateGoal(id) { $0.archivedAt = now }
    }

    public mutating func unarchiveGoal(_ id: UUID) {
        updateGoal(id) { $0.archivedAt = nil }
    }

    /// Starts a break that protects the streak from the start of today through the end of
    /// `until`'s day, or indefinitely. Whole days, since streaks judge days by their start.
    public mutating func startBreak(for id: UUID, until: Date?, at now: Date = .now, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: now)
        let end = until.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) } ?? .distantFuture
        guard end > now else { return }
        updateGoal(id) { goal in
            goal.breaks.removeAll { $0.end > now && $0.start <= now }
            goal.breaks.append(DateInterval(start: start, end: end))
        }
    }

    /// Ends the break in effect, keeping it in the history so past days stay protected.
    public mutating func endBreak(for id: UUID, at now: Date = .now) {
        updateGoal(id) { goal in
            goal.breaks = goal.breaks.compactMap { interval in
                guard interval.start <= now && now < interval.end else { return interval }
                return interval.start < now ? DateInterval(start: interval.start, end: now) : nil
            }
        }
    }
}

// MARK: - Logging

extension AppData {
    /// Records progress. Zero amounts are ignored; negative ones are corrections.
    @discardableResult
    public mutating func log(_ amount: Double, for goalID: UUID, at date: Date = .now, note: String = "", source: LogEntry.Source = .manual, bookID: UUID? = nil) -> LogEntry? {
        guard amount != 0, goal(goalID) != nil else { return nil }
        let entry = LogEntry(goalID: goalID, date: date, amount: amount, source: source, note: note, bookID: bookID)
        entries.append(entry)
        return entry
    }

    /// The one-tap action for a goal: a check-in, its quick-add step, the next milestone,
    /// or pages in the current book.
    public mutating func quickAdd(to goalID: UUID, at now: Date = .now) {
        guard let goal = goal(goalID) else { return }
        switch goal.kind {
        case .milestones:
            completeNextMilestone(in: goalID, at: now)
        case .books:
            if let book = goal.currentBook {
                logPages(Int(goal.quickAddStep.rounded()), in: book.id, of: goalID, at: now)
            }
        case .time, .count, .amount:
            log(goal.quickAddStep, for: goalID, at: now)
        }
    }

    public mutating func deleteEntry(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func updateEntry(_ entry: LogEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
    }
}

// MARK: - Focus sessions

extension AppData {
    /// Starts a session, first saving any session already running. Only time goals have
    /// sessions: their amounts are seconds, which other kinds would misread as their own unit.
    public mutating func startFocus(on goalID: UUID, planned: TimeInterval? = nil, at now: Date = .now, calendar: Calendar = .current) {
        guard goal(goalID)?.kind == .time else { return }
        stopFocus(at: now, calendar: calendar)
        session = FocusSession(goalID: goalID, plannedDuration: planned, start: now)
    }

    public mutating func pauseFocus(at now: Date = .now) {
        guard var current = session, let since = current.runningSince else { return }
        current.segments.append(DateInterval(start: since, end: max(since, now)))
        current.runningSince = nil
        session = current
    }

    public mutating func resumeFocus(at now: Date = .now) {
        guard var current = session, current.runningSince == nil else { return }
        current.runningSince = now
        session = current
    }

    public mutating func togglePauseFocus(at now: Date = .now) {
        if session?.isRunning == true { pauseFocus(at: now) } else { resumeFocus(at: now) }
    }

    /// Stops the session and logs its time: one entry per calendar day it touched, so a session
    /// across midnight credits both days. Sessions under a second are dropped.
    @discardableResult
    public mutating func stopFocus(at now: Date = .now, calendar: Calendar = .current) -> [LogEntry] {
        guard let finished = session else { return [] }
        session = nil
        var perDay: [Date: (start: Date, seconds: Double)] = [:]
        for segment in finished.allSegments(at: now) {
            var cursor = segment.start
            while cursor < segment.end {
                let dayStart = calendar.startOfDay(for: cursor)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? segment.end
                let end = min(dayEnd, segment.end)
                let existing = perDay[dayStart]
                perDay[dayStart] = (min(existing?.start ?? cursor, cursor), (existing?.seconds ?? 0) + end.timeIntervalSince(cursor))
                cursor = end
            }
        }
        let logged = perDay.values
            .filter { $0.seconds >= 1 }
            .sorted { $0.start < $1.start }
            .map { LogEntry(goalID: finished.goalID, date: $0.start, amount: $0.seconds.rounded(), source: .timer, note: finished.note) }
        entries.append(contentsOf: logged)
        return logged
    }

    public mutating func discardFocus() {
        session = nil
    }

    /// Stops the goal's running session, or starts one at the goal's default length.
    public mutating func toggleFocus(on goalID: UUID, at now: Date = .now, calendar: Calendar = .current) {
        if session?.goalID == goalID {
            stopFocus(at: now, calendar: calendar)
        } else {
            let minutes = goal(goalID)?.focusMinutes
            startFocus(on: goalID, planned: minutes.map { Double($0) * 60 }, at: now, calendar: calendar)
        }
    }

    /// The time goal a one-tap "focus" should start: the one timed most recently,
    /// else the first active time goal.
    public var suggestedFocusGoal: Goal? {
        let timeGoals = goals.filter { $0.kind == .time && !$0.isArchived }
        let lastTimed = entries.filter { $0.source == .timer }.max { $0.date < $1.date }?.goalID
        return timeGoals.first { $0.id == lastTimed } ?? timeGoals.first
    }

    public mutating func setSessionNote(_ note: String) {
        session?.note = note
    }
}

// MARK: - Milestones

extension AppData {
    public mutating func addMilestone(_ title: String, dueDate: Date? = nil, to goalID: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateGoal(goalID) { $0.milestones.append(Milestone(title: trimmed, dueDate: dueDate)) }
    }

    public mutating func toggleMilestone(_ milestoneID: UUID, in goalID: UUID, at now: Date = .now) {
        updateGoal(goalID) { goal in
            guard let index = goal.milestones.firstIndex(where: { $0.id == milestoneID }) else { return }
            goal.milestones[index].completedAt = goal.milestones[index].isDone ? nil : now
        }
    }

    public mutating func completeNextMilestone(in goalID: UUID, at now: Date = .now) {
        updateGoal(goalID) { goal in
            guard let index = goal.milestones.firstIndex(where: { !$0.isDone }) else { return }
            goal.milestones[index].completedAt = now
        }
    }

    public mutating func updateMilestone(_ milestone: Milestone, in goalID: UUID) {
        updateGoal(goalID) { goal in
            guard let index = goal.milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
            goal.milestones[index] = milestone
        }
    }

    public mutating func removeMilestone(_ milestoneID: UUID, from goalID: UUID) {
        updateGoal(goalID) { $0.milestones.removeAll { $0.id == milestoneID } }
    }

    public mutating func moveMilestones(in goalID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        updateGoal(goalID) { $0.milestones.move(fromOffsets: source, toOffset: destination) }
    }
}

// MARK: - Links

extension AppData {
    public mutating func upsertLink(_ link: GoalLink, in goalID: UUID) {
        updateGoal(goalID) { goal in
            if let index = goal.links.firstIndex(where: { $0.id == link.id }) {
                goal.links[index] = link
            } else {
                goal.links.append(link)
            }
        }
    }

    public mutating func removeLink(_ linkID: UUID, from goalID: UUID) {
        updateGoal(goalID) { $0.links.removeAll { $0.id == linkID } }
    }

    public mutating func moveLinks(in goalID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        updateGoal(goalID) { $0.links.move(fromOffsets: source, toOffset: destination) }
    }
}

// MARK: - Books

extension AppData {
    public mutating func upsertBook(_ book: Book, in goalID: UUID) {
        updateGoal(goalID) { goal in
            if let index = goal.books.firstIndex(where: { $0.id == book.id }) {
                goal.books[index] = book
            } else {
                goal.books.append(book)
            }
        }
    }

    public mutating func removeBook(_ bookID: UUID, from goalID: UUID) {
        updateGoal(goalID) { $0.books.removeAll { $0.id == bookID } }
        entries.removeAll { $0.goalID == goalID && $0.bookID == bookID }
    }

    /// Starts a book. A finished book is read again as a new copy from page one, so its original
    /// finish still counts.
    public mutating func startReading(_ bookID: UUID, in goalID: UUID, at now: Date = .now) {
        guard let book = goal(goalID)?.books.first(where: { $0.id == bookID }) else { return }
        if book.status == .finished {
            let reread = Book(title: book.title, author: book.author, totalPages: book.totalPages, status: .reading, notes: "",
                              link: book.link, coverURL: book.coverURL, addedAt: now, startedAt: now)
            upsertBook(reread, in: goalID)
            return
        }
        updateBook(bookID, in: goalID) { book in
            book.status = .reading
            book.startedAt = book.startedAt ?? now
            book.finishedAt = nil
        }
    }

    /// Marks a book finished, logging any pages between the bookmark and the end.
    public mutating func finishBook(_ bookID: UUID, in goalID: UUID, rating: Int? = nil, at now: Date = .now) {
        guard let book = goal(goalID)?.books.first(where: { $0.id == bookID }) else { return }
        if let total = book.totalPages, total > book.currentPage {
            log(Double(total - book.currentPage), for: goalID, at: now, bookID: bookID)
        }
        updateBook(bookID, in: goalID) { book in
            book.status = .finished
            book.startedAt = book.startedAt ?? now
            book.finishedAt = now
            if let total = book.totalPages { book.currentPage = total }
            if let rating { book.rating = rating }
        }
    }

    public mutating func abandonBook(_ bookID: UUID, in goalID: UUID) {
        updateBook(bookID, in: goalID) { $0.status = .abandoned }
    }

    /// Logs pages read and moves the bookmark. Starts the book if it was unread, and finishes it
    /// on reaching the last page.
    public mutating func logPages(_ pages: Int, in bookID: UUID, of goalID: UUID, at now: Date = .now, note: String = "") {
        guard pages != 0, let book = goal(goalID)?.books.first(where: { $0.id == bookID }) else { return }
        let target = max(0, book.currentPage + pages)
        let newPage = book.totalPages.map { min($0, target) } ?? target
        let delta = newPage - book.currentPage
        guard delta != 0 else { return }
        log(Double(delta), for: goalID, at: now, note: note, bookID: bookID)
        updateBook(bookID, in: goalID) { book in
            book.currentPage = newPage
            if book.status == .wantToRead { book.status = .reading }
            book.startedAt = book.startedAt ?? now
        }
        if let total = book.totalPages, newPage >= total, book.status != .finished {
            finishBook(bookID, in: goalID, at: now)
        }
    }

    /// Moves the bookmark to `page`, logging the difference.
    public mutating func setPage(_ page: Int, in bookID: UUID, of goalID: UUID, at now: Date = .now) {
        guard let book = goal(goalID)?.books.first(where: { $0.id == bookID }) else { return }
        logPages(page - book.currentPage, in: bookID, of: goalID, at: now)
    }

    private mutating func updateBook(_ bookID: UUID, in goalID: UUID, _ change: (inout Book) -> Void) {
        updateGoal(goalID) { goal in
            guard let index = goal.books.firstIndex(where: { $0.id == bookID }) else { return }
            change(&goal.books[index])
        }
    }
}

// MARK: - Collection helpers

extension Array {
    /// Reorders like SwiftUI's `move(fromOffsets:toOffset:)`, without depending on SwiftUI.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { self[$0] }
        let insertion = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { remove(at: index) }
        insert(contentsOf: moving, at: Swift.min(Swift.max(0, insertion), count))
    }
}
