import Foundation

/// What the Apple Watch shows, worked out on the iPhone: today's goals with their progress, the
/// timer, and each goal's one-tap action. A few kilobytes, so it can go out on every change.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var symbol: String
        public var color: GoalColor
        public var kind: GoalKind
        /// From 0 to 1 (and past 1 when beaten).
        public var progress: Double
        /// "45m / 2h", "2 / 4 workouts".
        public var progressText: String
        public var streak: Int
        public var streakUnit: String
        public var isComplete: Bool
        /// The one-tap action for goals without a timer: "+1", "+10 pages", "Done"; nil if none.
        public var actionTitle: String?
        /// The target alone ("2h", "4 workouts"), to show a fresh period's progress before the
        /// iPhone has sent one.
        public var targetText: String
        /// When the period this progress counts toward ends (nil for an overall target).
        public var periodEnd: Date?
        /// What reaching the target is called for this goal: "Done for today", "Done this week".
        public var doneText: String
        /// The day of a running challenge, and its length.
        public var challengeDay: Int?
        public var challengeLength: Int?
        /// The period the progress counts toward; nil from an iPhone that doesn't send it.
        public var period: GoalPeriod? = nil
        /// Where the book being read is up to ("Page 134 of 420"), on a books goal or one counted
        /// in pages; nil without one, or from an iPhone that doesn't send it.
        public var bookmark: String? = nil

        /// The item as its next period starts, before the iPhone has sent one: nothing done yet.
        func startingOver() -> Item {
            var item = self
            item.progress = 0
            item.isComplete = false
            item.progressText = kind == .time ? "0m / \(targetText)" : "0 / \(targetText)"
            return item
        }
    }

    /// Today's goals, in Today's order.
    public var items: [Item]
    /// The other active goals (not due today, on a break, or done for good), for the Goals page;
    /// nil from an iPhone that doesn't send them.
    public var others: [Item]?
    /// The last seven days, for the Week page; nil from an iPhone that doesn't send it.
    public var week: WatchWeek?
    public var session: FocusSession?
    public var rest: RestPeriod?
    /// Today's goals done, of all of them.
    public var done: Int
    public var total: Int
    public var generatedAt: Date
    /// The day the snapshot describes.
    public var day: DayID
    /// The iPhone's palette; nil from an iPhone that doesn't send one, and the watch draws in the
    /// default palette.
    public var palette: WatchPalette?

    public init(items: [Item] = [], session: FocusSession? = nil, rest: RestPeriod? = nil, done: Int = 0, total: Int = 0,
                generatedAt: Date = .distantPast, day: DayID = DayID(year: 2001, month: 1, day: 1), palette: WatchPalette? = nil,
                others: [Item]? = nil, week: WatchWeek? = nil) {
        self.items = items
        self.session = session
        self.rest = rest
        self.done = done
        self.total = total
        self.generatedAt = generatedAt
        self.day = day
        self.palette = palette
        self.others = others
        self.week = week
    }

    /// The snapshot as it stands at `date`: goals whose period has ended since (each day for a
    /// daily goal, at the week's end for a weekly one) start over with nothing done, so the
    /// watch never shows a finished period's progress as the current one's. The rest (streaks,
    /// the timer, the week) carries over until the iPhone sends a new snapshot.
    public func current(at date: Date, calendar: Calendar = .current) -> WatchSnapshot {
        func lapsed(_ item: Item) -> Bool { (item.periodEnd ?? .distantFuture) <= date }
        guard items.contains(where: lapsed) || (others ?? []).contains(where: lapsed) || DayID(date, calendar: calendar) > day else {
            return self
        }
        var fresh = self
        var reopened = 0
        fresh.items = items.map { item in
            guard lapsed(item) else { return item }
            if item.isComplete { reopened += 1 }
            return item.startingOver()
        }
        fresh.others = others?.map { lapsed($0) ? $0.startingOver() : $0 }
        fresh.done = max(0, done - reopened)
        fresh.day = max(day, DayID(date, calendar: calendar))
        return fresh
    }

    /// The most goals sent: a watch screen's worth, and then some.
    public static let itemLimit = 12
    /// The most other goals sent, so a long list can't outgrow what the watch connection carries.
    public static let otherLimit = 16

    /// A goal from today's list, or from the others.
    public func item(_ id: UUID) -> Item? { items.first { $0.id == id } ?? others?.first { $0.id == id } }

    /// The snapshot as sent: dates exact, like the data file.
    public func encoded() throws -> Data { try DateCoding.encoder().encode(self) }

    public init(encoded: Data) throws {
        self = try DateCoding.decoder().decode(Self.self, from: encoded)
    }
}

/// The palette the watch draws in: the iPhone's active palette as it looks in dark mode, the
/// watch's only appearance, so a goal has the same color on the wrist as on the phone.
public struct WatchPalette: Codable, Equatable, Sendable {
    public var accent: OKLCH
    /// One per `GoalColor`, in `GoalColor.allCases` order.
    public var swatches: [OKLCH]

    public init(_ palette: Palette) {
        accent = Self.rounded(palette.dark.accent)
        swatches = palette.dark.swatches.map(Self.rounded)
    }

    /// The default palette, for a snapshot from an iPhone that doesn't send one.
    public static var standard: WatchPalette { WatchPalette(.standard) }

    public func swatch(_ color: GoalColor) -> OKLCH {
        swatches.indices.contains(color.index) ? swatches[color.index] : Self.standard.swatches[color.index]
    }

    private enum CodingKeys: String, CodingKey { case accent, swatches }

    /// Never fails the snapshot it comes in: whatever can't be read is the default palette's.
    public init(from decoder: Decoder) throws {
        let fallback = Self.standard
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        accent = (try? c?.decode(OKLCH.self, forKey: .accent)) ?? fallback.accent
        let sent = (try? c?.decode([OKLCH].self, forKey: .swatches)) ?? []
        swatches = GoalColor.allCases.indices.map { $0 < sent.count ? sent[$0] : fallback.swatches[$0] }
    }

    /// What's worth sending: four decimals of lightness and chroma, two of hue. Rounded here
    /// rather than when written, so a snapshot reads back exactly as it was made.
    private static func rounded(_ color: OKLCH) -> OKLCH {
        OKLCH((color.lightness * 10_000).rounded() / 10_000, (color.chroma * 10_000).rounded() / 10_000,
              Hue.normalized((color.hue * 100).rounded() / 100))
    }
}

/// The keys of the messages between the iPhone and the watch.
public enum WatchMessageKey {
    /// An encoded `WatchSnapshot`, in the application context and in replies.
    public static let snapshot = "snapshot"
    /// An encoded `WatchAction`.
    public static let action = "action"
    /// Asks for a fresh snapshot.
    public static let refresh = "refresh"
}

/// Something done on the watch, carried out on the iPhone. Each says exactly what was tapped,
/// against what the watch showed, so a late or repeated delivery can't undo it: a Stop for a
/// session that already ended does nothing, where a toggle would start it again.
public enum WatchAction: Codable, Equatable, Sendable {
    case start(goal: UUID)
    /// Stops the session on `goal` that started at `sessionStart`, if it's still running.
    case stop(goal: UUID, sessionStart: Date)
    case setPaused(goal: UUID, sessionStart: Date, paused: Bool)
    case quickAdd(goal: UUID)
    /// Ends the break that started at `restStart` and starts the next block.
    case startNextBlock(restStart: Date)
    case endRest(restStart: Date)
    /// Makes a goal. An iPhone that doesn't know this can't read the command, and leaves it.
    case addGoal(goal: WatchNewGoal)
}

/// A goal made on the watch: one of the templates, or a name and a target. Its id is made on the
/// watch, so a command delivered twice adds it once.
public struct WatchNewGoal: Codable, Equatable, Sendable {
    public var id: UUID
    /// A `GoalTemplate` id. When it names one, the template is the goal; the rest describes it
    /// for an iPhone that doesn't have that template.
    public var template: String?
    public var name: String
    /// `.time` or `.count`; anything else makes a count.
    public var kind: GoalKind
    /// `.daily` or `.weekly`; anything else makes a daily goal.
    public var period: GoalPeriod
    /// Seconds for a time goal, times for a count.
    public var target: Double

    public init(id: UUID = UUID(), template: String? = nil, name: String, kind: GoalKind, period: GoalPeriod, target: Double) {
        self.id = id
        self.template = template
        self.name = name
        self.kind = kind
        self.period = period
        self.target = target
    }

    /// The template's goal as the watch offers it.
    public init(template: GoalTemplate) {
        self.init(template: template.id, name: template.prototype.name, kind: template.prototype.kind,
                  period: template.prototype.period, target: template.prototype.target)
    }

    /// The goal to add, in a color none of `goals` has when it's not a template's; nil for a
    /// blank name or a target that isn't a positive number.
    func goal(besides goals: [Goal], at date: Date) -> Goal? {
        var goal: Goal
        if let template, let match = GoalTemplate.all.first(where: { $0.id == template }) {
            goal = match.makeGoal(at: date)
        } else {
            let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: GoalKind = self.kind == .time ? .time : .count
            let target = kind == .count ? self.target.rounded() : self.target
            guard !name.isEmpty, target.isFinite, target > 0 else { return nil }
            goal = Goal(name: String(name.prefix(80)), color: GoalColor.suggested(besides: goals), kind: kind,
                        period: period == .weekly ? .weekly : .daily, target: target, createdAt: date)
        }
        goal.id = id
        return goal
    }
}

/// An action with when it was tapped, and an id so it's carried out once however often it
/// arrives (a reply lost on the way back gets it sent again).
public struct WatchCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var action: WatchAction
    public var date: Date

    public init(id: UUID = UUID(), action: WatchAction, date: Date = .now) {
        self.id = id
        self.action = action
        self.date = date
    }

    public func encoded() throws -> Data { try DateCoding.encoder().encode(self) }

    public init(encoded: Data) throws {
        self = try DateCoding.decoder().decode(Self.self, from: encoded)
    }
}

extension ProgressEngine {
    public func watchSnapshot(now: Date) -> WatchSnapshot {
        let today = stackOrdered(todayGoals(now: now))
        var items = today.prefix(WatchSnapshot.itemLimit).map { item(for: $0, now: now) }
        // A running timer's goal always makes the list, even when Today wouldn't show it.
        if let session = data.session, !items.contains(where: { $0.id == session.goalID }), let goal = goal(session.goalID) {
            items.insert(item(for: goal, now: now), at: 0)
        }
        let summary = todaySummary(now: now)
        let shown = Set(items.map(\.id))
        let others = stackOrdered(activeGoals.filter { !shown.contains($0.id) })
            .prefix(WatchSnapshot.otherLimit)
            .map { item(for: $0, now: now) }
        return WatchSnapshot(items: items, session: data.session, rest: data.rest, done: summary.done, total: summary.total,
                             generatedAt: now, day: DayID(now, calendar: calendar), palette: WatchPalette(data.preferences.activePalette),
                             others: others, week: watchWeek(now: now))
    }

    private func item(for goal: Goal, now: Date) -> WatchSnapshot.Item {
        let streak = streak(for: goal, now: now)
        let challenge = challengeStatus(for: goal, now: now).flatMap { $0.isFinished || $0.dayNumber == 0 ? nil : $0 }
        return WatchSnapshot.Item(
            id: goal.id, name: goal.name, symbol: goal.symbol, color: goal.color, kind: goal.kind,
            progress: progress(for: goal, now: now),
            progressText: goal.kind == .milestones
                ? "\(goal.milestones.count(where: \.isDone)) / \(goal.milestones.count) milestones"
                : goal.progressText(currentAmount(for: goal, now: now), target: target(for: goal)),
            streak: streak.current, streakUnit: streak.unit, isComplete: isComplete(goal, now: now),
            actionTitle: actionTitle(for: goal),
            targetText: goal.kind == .milestones ? "\(goal.milestones.count) milestones" : goal.format(target(for: goal)),
            periodEnd: goal.effectivePeriod == .total ? nil : interval(of: goal.effectivePeriod, containing: now).end,
            doneText: Self.doneText(for: goal),
            challengeDay: challenge?.dayNumber, challengeLength: challenge?.challenge.days,
            period: goal.effectivePeriod,
            bookmark: goal.kind == .books || goal.tracksPages ? goal.currentBook.map(Self.bookmark) : nil)
    }

    /// "Page 134 of 420", or "Page 134" without a page count.
    private static func bookmark(_ book: Book) -> String {
        book.totalPages.map { "Page \(book.currentPage) of \($0)" } ?? "Page \(book.currentPage)"
    }

    private static func doneText(for goal: Goal) -> String {
        if goal.kind == .milestones { return "All done" }
        return switch goal.effectivePeriod {
        case .daily: "Done for today"
        case .weekly: "Done this week"
        case .monthly: "Done this month"
        case .yearly: "Done this year"
        case .total: "Target reached"
        }
    }

    private func actionTitle(for goal: Goal) -> String? {
        switch goal.kind {
        case .time: nil
        case .count, .amount: goal.kind == .count && goal.quickAddStep == 1 ? "+1" : "+\(goal.format(goal.quickAddStep))"
        case .milestones: goal.milestones.contains { !$0.isDone } ? "Done" : nil
        case .books: goal.currentBook == nil ? nil : "+\(Formatting.number(goal.quickAddStep)) pages"
        }
    }
}

extension AppData {
    /// Carries out a command from the watch, dated when it was tapped (never later than `now`),
    /// so a Stop delivered hours late doesn't count the hours in between.
    public mutating func apply(_ command: WatchCommand, now: Date = .now, calendar: Calendar = .current) {
        let tapped = min(command.date, now)
        func isShown(_ goal: UUID, _ start: Date) -> Bool {
            guard let session, session.goalID == goal else { return false }
            return abs(session.startedAt.timeIntervalSince(start)) < 0.001
        }
        func isShownRest(_ start: Date) -> Bool {
            guard let rest else { return false }
            return abs(rest.start.timeIntervalSince(start)) < 0.001
        }
        // The timer's last change on any device: a tap from before it can't reach back past it.
        let lastTimerChange = sync.stamp(SyncState.session)
        switch command.action {
        case .start(let goal):
            guard let target = self.goal(goal), target.kind == .time, !target.isArchived, session?.goalID != goal else { return }
            let start = max(tapped, lastTimerChange, session?.startedAt ?? tapped)
            startFocus(on: goal, planned: defaultFocusLength(for: goal), at: min(start, now), calendar: calendar)
        case .stop(let goal, let start):
            guard isShown(goal, start) else { return }
            stopFocus(at: max(tapped, start), calendar: calendar)
        case .setPaused(let goal, let start, let paused):
            guard isShown(goal, start), let current = session, current.isRunning == paused else { return }
            if paused {
                pauseFocus(at: max(tapped, current.runningSince ?? tapped))
            } else {
                resumeFocus(at: min(max(tapped, current.segments.last?.end ?? tapped), now))
            }
        case .quickAdd(let goal):
            quickAdd(to: goal, at: tapped)
        case .startNextBlock(let restStart):
            guard isShownRest(restStart) else { return }
            startNextBlock(at: max(tapped, restStart), calendar: calendar)
        case .endRest(let restStart):
            guard isShownRest(restStart) else { return }
            endRest()
        case .addGoal(let new):
            // Once, and not again once deleted: a late copy of the command mustn't bring it back.
            guard goal(new.id) == nil, sync.tombstones[SyncState.goal(new.id)] == nil,
                  let made = new.goal(besides: goals, at: tapped) else { return }
            upsert(made)
        }
    }
}
