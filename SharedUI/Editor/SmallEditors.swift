import MomentumCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Log an amount at a chosen time, with a note: forgotten sessions, past workouts, words written.
/// With an existing entry, edits it instead. A goal that follows something (a book, a course, a
/// series, a video) can also log where it's up to, a time goal a span from one time to another,
/// and a count or an amount can say how long it took.
struct LogProgressSheet: View {
    /// How a new entry is given: an amount, the position reached, or a span of time.
    enum Mode: Hashable {
        case amount
        case position
        case span
    }

    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    let entry: LogEntry?
    @State private var mode: Mode = .amount
    @State private var amount: Double
    @State private var minutes: Int
    /// The minutes shown when the sheet opened: unchanged means keep the entry's exact amount.
    private let initialMinutes: Int
    @State private var date: Date
    @State private var note: String
    /// The position typed: a page, lesson or episode number, or "1:23:40" into a video.
    @State private var positionText: String
    @State private var spanStart: Date
    @State private var spanEnd: Date
    /// How long it took, in minutes, on a count or an amount.
    @State private var tookMinutes: Double?

    /// `day` presets the date to that day (at the current time of day, or noon for today's future),
    /// for logging a day that was missed.
    init(goal: Goal, entry: LogEntry? = nil, day: Date? = nil) {
        self.goal = goal
        self.entry = entry
        let value = entry?.amount ?? goal.quickAddStep
        _amount = State(initialValue: value)
        let wholeMinutes = Int((abs(value) / 60).rounded())
        let shownMinutes = value < 0 ? -max(1, wholeMinutes) : max(1, wholeMinutes)
        _minutes = State(initialValue: shownMinutes)
        initialMinutes = shownMinutes
        let moment = entry?.date ?? day.map(Self.moment(on:)) ?? .now
        _date = State(initialValue: moment)
        _note = State(initialValue: entry?.note ?? "")
        _positionText = State(initialValue: goal.currentBook.map { Self.positionField(goal: goal, item: $0) } ?? "")
        // A span ends at the minute the sheet opened (or the day's moment), and runs one quick-add step.
        let clock = Calendar.current.dateComponents([.hour, .minute], from: moment)
        let end = Calendar.current.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: moment) ?? moment
        _spanEnd = State(initialValue: end)
        _spanStart = State(initialValue: end.addingTimeInterval(-max(60, goal.quickAddStep)))
        _tookMinutes = State(initialValue: entry?.duration.map { $0 / 60 })
    }

    /// The current time of day on `day`, kept in the past.
    private static func moment(on day: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: .now)
        let moment = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
        return min(moment, .now)
    }

    /// An item's position as the field shows it: "134", or "1:23:40" into a video.
    private static func positionField(goal: Goal, item: Book) -> String {
        goal.follows == .video ? Formatting.clock(Double(item.currentPage)) : "\(item.currentPage)"
    }

    /// Logs that move a book's bookmark (or a course's place) have their amount fixed once logged.
    private var amountIsLocked: Bool { entry?.bookID != nil }

    /// Editing a correction (a negative entry) keeps it negative.
    private var isCorrection: Bool { (entry?.amount ?? 0) < 0 }

    /// The amount to save: the entry's exact amount unless its duration was actually changed,
    /// so editing a note never rounds a 25m 40s session to 26m.
    private var amountToSave: Double {
        guard goal.kind == .time else { return amount }
        if let entry, minutes == initialMinutes { return entry.amount }
        return Double(minutes * 60)
    }

    /// The ways a new entry can be given; none to choose between when editing one.
    private var modes: [Mode] {
        guard entry == nil else { return [] }
        if goal.kind == .time { return [.amount, .span, .position] }
        return goal.follows == nil ? [] : [.amount, .position]
    }

    /// The unit after the amount: pages on a books goal, whose target counts books.
    private var amountUnit: String { goal.kind == .books ? "pages" : goal.displayUnit }

    /// Whether the entry can say how long it took: counts and amounts, given as an amount.
    private var showsTook: Bool { (goal.kind == .count || goal.kind == .amount) && (entry != nil || mode == .amount) }

    private var tookSeconds: TimeInterval? { LogEntry.validDuration(tookMinutes.map { $0 * 60 }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                GoalIcon(goal: goal, size: 40)
                VStack(alignment: .leading) {
                    Text(entry == nil ? "Log progress" : "Edit entry").font(.title3.weight(.bold))
                    Text(goal.name).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            Form {
                if modes.count > 1 {
                    Picker("Log", selection: $mode) {
                        ForEach(modes, id: \.self) { Text(title(of: $0)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                switch mode {
                case .amount: amountRows
                case .position: positionRows
                case .span: spanRows
                }
                if showsTook { tookRow }
                TextField("Note", text: $note, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...3)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                if let entry {
                    Button("Delete", role: .destructive) {
                        store.deleteEntry(entry)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Log" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .primaryActionStyle(goal.tint)
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .sheetFrame(width: 460, height: 480)
        .background(Aurora(accent: goal.tint))
    }

    /// The segment for a mode, in the goal's words: "Pages read", "Finished lesson", "From–to".
    private func title(of mode: Mode) -> String {
        let parts = goal.followedParts ?? (one: "page", many: "pages")
        switch mode {
        case .span:
            return "From–to"
        case .amount:
            switch goal.follows {
            case .book: return "Pages read"
            case .course: return "\(parts.many.capitalized) done"
            case .series: return "\(parts.many.capitalized) watched"
            case .video, nil: return goal.kind == .time ? "Duration" : "Amount"
            }
        case .position:
            switch goal.follows {
            case .book: return "I'm on page"
            case .course: return "Finished \(parts.one)"
            case .series: return "Up to \(parts.one)"
            case .video, nil: return "Video"
            }
        }
    }

    @ViewBuilder
    private var amountRows: some View {
        if goal.kind == .time {
            Stepper(value: $minutes, in: isCorrection ? -720...(-1) : 1...720, step: entry == nil ? 5 : 1) {
                LabeledContent(isCorrection ? "Correction" : "Duration",
                               value: (isCorrection ? "−" : "") + Formatting.duration(Double(abs(minutes) * 60)))
            }
            // Time watched in a video moved its position, so it stays as logged, like pages.
            .disabled(amountIsLocked)
        } else {
            LabeledContent("Amount") {
                HStack {
                    TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .disabled(amountIsLocked)
                    Text(amountUnit).foregroundStyle(.secondary)
                }
            }
        }
        DatePicker("When", selection: $date, in: ...Date.now)
    }

    @ViewBuilder
    private var positionRows: some View {
        if let item = goal.currentBook {
            LabeledContent(item.title, value: goal.positionText(of: item))
            LabeledContent(positionLabel) {
                TextField(positionLabel, text: $positionText, prompt: Text(goal.follows == .video ? "1:23:40" : "0"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    #if os(iOS)
                    .keyboardType(goal.follows == .video ? .numbersAndPunctuation : .numberPad)
                    #endif
            }
            Text(positionCaption(item))
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker("When", selection: $date, in: ...Date.now)
        } else {
            let kind = goal.follows ?? .video
            Text(addPrompt(kind))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add \(kind.title)…") { store.sheet = .book(goalID: goal.id, book: nil) }
        }
    }

    /// "Page", "Lesson", "Episode", or "Watched up to" for a video.
    private var positionLabel: String {
        guard let part = goal.followedParts?.one else { return "Watched up to" }
        return part.capitalized
    }

    /// The position typed, in the goal's unit (seconds into a video); nil if it doesn't read.
    private var typedPosition: Int? {
        if goal.follows == .video { return Formatting.seconds(fromClock: positionText) }
        return Int(positionText.trimmingCharacters(in: .whitespaces)).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// What logging the typed position does: "Logs 3 lessons.", "Takes back 20 pages."
    private func positionCaption(_ item: Book) -> String {
        guard let typed = typedPosition else {
            return goal.follows == .video ? "Type the time you reached, like 1:23:40 or 45 for minutes." : "Type a whole number."
        }
        let total = item.totalPages.flatMap { $0 > 0 ? $0 : nil }
        let reached = total.map { min($0, typed) } ?? typed
        let change = reached - item.currentPage
        if change == 0 { return "That's where you are now." }
        let amount = goal.formatParts(Double(abs(change)))
        guard change > 0 else { return "Takes back \(amount)." }
        let finishes = total.map { reached >= $0 } ?? false
        return finishes ? "Logs \(amount), and finishes the \(goal.follows?.noun ?? "book")." : "Logs \(amount)."
    }

    private func addPrompt(_ kind: FollowKind) -> String {
        switch kind {
        case .book: "Add the book you're reading, then log the page you reach: the pages in between count."
        case .course: "Add the course you're taking, then log the lesson you finish: the ones in between count."
        case .series: "Add the series you're watching, then log the episode you reach: the ones in between count."
        case .video: "Add the video you're watching and its length, then log the time you reach: the time in between counts."
        }
    }

    @ViewBuilder
    private var spanRows: some View {
        DatePicker("From", selection: $spanStart, in: ...Date.now)
        DatePicker("To", selection: $spanEnd, displayedComponents: .hourAndMinute)
        LabeledContent("Duration", value: spanIsValid ? Formatting.duration(spanSeconds) : "–")
    }

    /// The end of the span: the To time on the From day, or the next day's if it's earlier.
    private var spanEndMoment: Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: spanEnd)
        let sameDay = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: spanStart) ?? spanStart
        return sameDay > spanStart ? sameDay : (calendar.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay)
    }

    private var spanSeconds: Double { spanEndMoment.timeIntervalSince(spanStart).rounded() }

    private var spanIsValid: Bool { spanSeconds >= 60 && spanSeconds < 24 * 3600 }

    private var tookRow: some View {
        LabeledContent("Took") {
            HStack {
                TextField("Took", value: $tookMinutes, format: .number.precision(.fractionLength(0...1)), prompt: Text("Optional"))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("min").foregroundStyle(.secondary)
                if let pace = tookSeconds.flatMap({ goal.paceText(amount: amount, duration: $0) }) {
                    Text(pace).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }

    private var canSave: Bool {
        guard entry == nil else { return goal.kind == .time || amount != 0 }
        switch mode {
        case .amount:
            return goal.kind == .time || amount != 0
        case .span:
            return spanIsValid
        case .position:
            guard let item = goal.currentBook, let typed = typedPosition else { return false }
            return typed != item.currentPage
        }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if var edited = entry {
            if !amountIsLocked { edited.amount = amountToSave }
            edited.date = date
            edited.note = trimmed
            if goal.kind != .time { edited.duration = tookSeconds }
            store.updateEntry(edited)
            dismiss()
            return
        }
        switch mode {
        case .amount:
            store.log(amountToSave, for: goal, at: date, note: trimmed, duration: showsTook ? tookSeconds : nil)
        case .span:
            store.log(spanSeconds, for: goal, at: spanStart, note: trimmed)
        case .position:
            guard let item = goal.currentBook, let position = typedPosition else { return }
            let goalID = goal.id
            let when = date
            store.perform("Log Progress") { $0.setPage(position, in: item.id, of: goalID, at: when, note: trimmed) }
        }
        dismiss()
    }
}

/// Add or edit a link: a URL, or a local file or folder picked from disk.
struct LinkEditor: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    let link: GoalLink?
    @State private var title: String
    @State private var address: String
    @State private var bookmark: Data?
    /// The file path the bookmark was made for; a retyped path needs a new one.
    @State private var bookmarkPath: String?
    @State private var opensWithFocus: Bool

    init(goalID: UUID, link: GoalLink?) {
        self.goalID = goalID
        self.link = link
        _title = State(initialValue: link?.title ?? "")
        _address = State(initialValue: link.map { $0.url.isFileURL ? $0.url.path(percentEncoded: false) : $0.url.absoluteString } ?? "")
        _bookmark = State(initialValue: link?.bookmark)
        _bookmarkPath = State(initialValue: link.flatMap { $0.url.isFileURL ? $0.url.path(percentEncoded: false) : nil })
        _opensWithFocus = State(initialValue: link?.opensWithFocus ?? false)
    }

    /// Accepts full URLs, app links like notion:// or obsidian://, bare domains, and file paths.
    private var url: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(filePath: (trimmed as NSString).expandingTildeInPath)
        }
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty, trimmed.contains(":") {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    var body: some View {
        let goal = store.goal(goalID)
        VStack(alignment: .leading, spacing: 0) {
            Text(link == nil ? "Add link" : "Edit link")
                .font(.title3.weight(.bold))
                .padding(20)
            Form {
                TextField("Address", text: $address, prompt: Text("https://…, notion://…, or a file"))
                #if os(macOS)
                HStack {
                    Spacer()
                    Button("Choose File or Folder…", action: chooseFile)
                        .controlSize(.small)
                }
                #endif
                TextField("Title", text: $title, prompt: Text(url.map { GoalLink(title: "", url: $0).displayTitle } ?? "Optional"))
                if goal?.kind == .time {
                    Toggle("Open when a focus session starts", isOn: $opensWithFocus)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(link == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .primaryActionStyle(goal?.tint ?? .accent)
                    .disabled(url == nil)
            }
            .padding(16)
        }
        .sheetFrame(width: 460, height: 330)
        .background(Aurora(accent: goal?.tint))
    }

    #if os(macOS)
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach"
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        address = picked.path(percentEncoded: false)
        bookmark = LinkOpener.bookmark(for: picked)
        bookmarkPath = picked.path(percentEncoded: false)
        if title.isEmpty { title = picked.lastPathComponent }
    }
    #endif

    private func save() {
        guard let url else { return }
        var updated = link ?? GoalLink(title: "", url: url)
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.url = url
        let matchingBookmark = bookmarkPath == url.path(percentEncoded: false) ? bookmark : nil
        updated.bookmark = url.isFileURL ? (matchingBookmark ?? LinkOpener.bookmark(for: url)) : nil
        updated.opensWithFocus = opensWithFocus
        store.perform(link == nil ? "Add Link" : "Edit Link") { $0.upsertLink(updated, in: goalID) }
        dismiss()
    }
}

/// Add or edit a book on a reading goal, or what another goal follows: a course, a series, or a
/// video, whose length and position are a time.
struct BookEditor: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    let book: Book?
    /// What the goal follows; a books goal reads books.
    let kind: FollowKind
    @State private var draft: Book
    /// The length: pages, lessons or episodes, or "1:30:00" for a video.
    @State private var pagesText: String
    /// A video's position, as "1:23:40".
    @State private var positionText: String
    @State private var linkText: String
    @State private var query = ""
    @State private var results: [BookSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?

    init(goalID: UUID, book: Book?, follows: FollowKind = .book) {
        self.goalID = goalID
        self.book = book
        kind = follows
        let initial = book ?? Book(title: "")
        _draft = State(initialValue: initial)
        let timed = follows == .video
        _pagesText = State(initialValue: initial.totalPages.map { timed ? Formatting.clock(Double($0)) : String($0) } ?? "")
        _positionText = State(initialValue: Formatting.clock(Double(initial.currentPage)))
        _linkText = State(initialValue: initial.link?.absoluteString ?? "")
    }

    /// The goal's parts, plural and capitalized: "Pages", "Lessons", "Episodes".
    private var partsTitle: String { (store.goal(goalID)?.followedParts?.many ?? "pages").capitalized }

    /// The length typed, in the goal's unit (seconds for a video), if it's a positive number.
    private var typedLength: Int? {
        let text = pagesText.trimmingCharacters(in: .whitespaces)
        let length = kind == .video ? Formatting.seconds(fromClock: text) : Int(text)
        return length.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        let goal = store.goal(goalID)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                BookCover(book: draft.title.isEmpty ? Book(title: "?") : draft, tint: goal?.tint ?? .accent, height: 58)
                VStack(alignment: .leading) {
                    Text(book == nil ? "Add \(kind.noun)" : "Edit \(kind.noun)").font(.title3.weight(.bold))
                    Text(draft.title.isEmpty ? subtitlePrompt : draft.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(20)
            Form {
                if kind == .book { searchSection }
                details
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(book == nil ? "Add \(kind.title)" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .primaryActionStyle(goal?.tint ?? .accent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .sheetFrame(width: 480, height: 640)
        .background(Aurora(accent: goal?.tint))
        .task(id: query) { await search() }
        .onAppear {
            // What's added to a goal that follows something is the one in progress, from any point.
            if book == nil, let goal, goal.kind != .books, goal.follows != nil { draft.status = .reading }
        }
    }

    private var subtitlePrompt: String {
        switch kind {
        case .book: "Title, author and pages"
        case .course: "Title, teacher and \(partsTitle.lowercased())"
        case .series: "Title, channel and \(partsTitle.lowercased())"
        case .video: "Title, channel and length"
        }
    }

    private var searchSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a book", text: $query, prompt: Text("Search Open Library by title or author"))
                    .labelsHidden()
                if isSearching { ProgressView().controlSize(.small) }
            }
            ForEach(results.prefix(5)) { result in
                Button { apply(result) } label: { SearchResultRow(result: result) }
                    .buttonStyle(.plain)
            }
            if let searchError {
                Text(searchError).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var details: some View {
        TextField("Title", text: $draft.title)
        TextField(authorTitle, text: $draft.author, prompt: Text(kind == .book ? "" : "Optional"))
        TextField(lengthTitle, text: $pagesText, prompt: Text(lengthPrompt))
        Picker("Status", selection: $draft.status) {
            ForEach(BookStatus.allCases) { Label($0.title(for: kind), systemImage: $0.symbolName).tag($0) }
        }
        if draft.status == .reading {
            if kind == .video {
                TextField("Watched up to", text: $positionText, prompt: Text("1:23:40"))
            } else {
                Stepper(value: $draft.currentPage, in: 0...max(1, typedLength ?? 10_000), step: 1) {
                    LabeledContent(positionTitle, value: "\(draft.currentPage)")
                }
            }
        }
        if draft.status == .finished {
            LabeledContent("Rating") {
                StarRating(rating: draft.rating ?? 0) { draft.rating = $0 == 0 ? nil : $0 }
                    .font(.title3)
            }
        }
        TextField("Link", text: $linkText, prompt: Text(linkPrompt))
        TextField("Notes", text: $draft.notes, prompt: Text("Quotes, thoughts…"), axis: .vertical)
            .lineLimit(2...5)
    }

    /// "Author", "Teacher", "Channel".
    private var authorTitle: String {
        switch kind {
        case .book: "Author"
        case .course: "Teacher"
        case .series, .video: "Channel"
        }
    }

    /// "Pages", "Lessons", "Episodes", or a video's "Length".
    private var lengthTitle: String { kind == .video ? "Length" : partsTitle }

    private var lengthPrompt: String { kind == .video ? "1:30:00, optional, enables progress" : "Optional, enables progress" }

    /// "Current page", "Lessons done", "Episodes watched".
    private var positionTitle: String {
        switch kind {
        case .book: "Current page"
        case .course: "\(partsTitle) done"
        case .series, .video: "\(partsTitle) watched"
        }
    }

    private var linkPrompt: String {
        switch kind {
        case .book: "Store, Goodreads or ebook (optional)"
        case .course: "The course's page (optional)"
        case .series, .video: "Where to watch it (optional)"
        }
    }

    /// Searches after typing pauses, so each keystroke doesn't send a request.
    private func search() async {
        let text = query
        guard OpenLibrary.searchURL(for: text) != nil else {
            results = []
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await OpenLibrary.search(text)
            guard !Task.isCancelled else { return }
            results = found
            searchError = found.isEmpty ? "No books found for \"\(text)\"." : nil
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            results = []
            searchError = "Couldn't reach Open Library. You can still fill the details in by hand."
        }
    }

    private func apply(_ result: BookSearchResult) {
        draft.title = result.title
        draft.author = result.author
        draft.coverURL = result.coverURL
        pagesText = result.pages.map(String.init) ?? pagesText
        linkText = result.link.absoluteString
        results = []
        query = ""
    }

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = draft.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalPages = typedLength
        let trimmedLink = linkText.trimmingCharacters(in: .whitespaces)
        let link = trimmedLink.isEmpty ? nil : URL(string: trimmedLink.contains("://") ? trimmedLink : "https://\(trimmedLink)")
        var typed = draft
        // A video's position is typed as a time; one that doesn't read leaves it where it was.
        if kind == .video, let seconds = Formatting.seconds(fromClock: positionText) { typed.currentPage = seconds }
        let edited = typed
        let original = book
        let now = Date.now
        // Merge onto the book as stored now: pages logged from a widget while this sheet was open
        // must not be undone by the copy taken when it opened.
        store.perform(book == nil ? "Add \(kind.title)" : "Edit \(kind.title)") { data in
            var current = original.flatMap { original in data.goal(goalID)?.books.first { $0.id == original.id } } ?? edited
            current.title = title
            current.author = author
            current.totalPages = totalPages
            current.rating = edited.rating
            current.notes = edited.notes
            current.link = link
            current.coverURL = edited.coverURL
            let statusChanged = original == nil || edited.status != original?.status
            // Finishing goes through finishBook below, which also logs the pages left.
            let finishing = statusChanged && edited.status == .finished && current.status != .finished
            if statusChanged && !finishing { current.status = edited.status }
            if current.status == .reading && current.startedAt == nil { current.startedAt = now }
            if current.status != .finished { current.finishedAt = nil }
            // Only a page the user changed in this sheet moves the bookmark, logged as pages read.
            var pageDelta = 0
            if let original, edited.currentPage != original.currentPage, current.status == .reading {
                pageDelta = edited.currentPage - current.currentPage
                current.currentPage = edited.currentPage
            }
            if let totalPages { current.currentPage = min(current.currentPage, totalPages) }
            data.upsertBook(current, in: goalID)
            if pageDelta != 0 {
                data.log(Double(pageDelta), for: goalID, at: now, bookID: current.id)
            }
            if finishing {
                data.finishBook(current.id, in: goalID, rating: edited.rating, at: now)
            }
        }
        dismiss()
    }
}

/// A catalog match: cover, title, author, year and length.
private struct SearchResultRow: View {
    let result: BookSearchResult
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            BookCover(book: result.makeBook(), tint: .accent, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text([result.author, result.year.map(String.init), result.pages.map { "\($0) pages" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(isHovered ? Color.accent : Color.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
