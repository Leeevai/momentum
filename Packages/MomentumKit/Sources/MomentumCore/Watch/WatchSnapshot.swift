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
        /// The target alone ("2h", "4 workouts"), to show a fresh day's progress before the iPhone
        /// has sent one.
        public var targetText: String
        /// Whether progress starts over each day.
        public var isDaily: Bool
        /// The day of a running challenge, and its length.
        public var challengeDay: Int?
        public var challengeLength: Int?
    }

    public var items: [Item]
    public var session: FocusSession?
    public var rest: RestPeriod?
    /// Today's goals done, of all of them.
    public var done: Int
    public var total: Int
    public var generatedAt: Date
    /// The day the snapshot describes.
    public var day: DayID

    public init(items: [Item] = [], session: FocusSession? = nil, rest: RestPeriod? = nil, done: Int = 0, total: Int = 0,
                generatedAt: Date = .distantPast, day: DayID = DayID(year: 2001, month: 1, day: 1)) {
        self.items = items
        self.session = session
        self.rest = rest
        self.done = done
        self.total = total
        self.generatedAt = generatedAt
        self.day = day
    }

    /// The snapshot as it stands on `today`: if it describes an earlier day, daily goals start
    /// over (nothing done yet), so the watch never shows yesterday's progress as today's. The
    /// rest (streaks, weekly progress, the timer) carries over until the iPhone sends a new one.
    public func current(on today: DayID) -> WatchSnapshot {
        guard day < today else { return self }
        var fresh = self
        fresh.items = items.map { item in
            guard item.isDaily else { return item }
            var item = item
            item.progress = 0
            item.isComplete = false
            item.progressText = item.kind == .time ? "0m / \(item.targetText)" : "0 / \(item.targetText)"
            return item
        }
        fresh.done = fresh.items.count { $0.isComplete }
        fresh.day = today
        return fresh
    }

    /// The most goals sent: a watch screen's worth, and then some.
    public static let itemLimit = 12

    public func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    /// The snapshot as sent: dates exact, like the data file.
    public func encoded() throws -> Data { try DateCoding.encoder().encode(self) }

    public init(encoded: Data) throws {
        self = try DateCoding.decoder().decode(Self.self, from: encoded)
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
    case startNextBlock
    case endRest
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
        return WatchSnapshot(items: items, session: data.session, rest: data.rest, done: summary.done, total: summary.total,
                             generatedAt: now, day: DayID(now, calendar: calendar))
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
            isDaily: goal.effectivePeriod == .daily,
            challengeDay: challenge?.dayNumber, challengeLength: challenge?.challenge.days)
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
        switch command.action {
        case .start(let goal):
            guard let target = self.goal(goal), target.kind == .time, !target.isArchived, session?.goalID != goal else { return }
            startFocus(on: goal, at: max(tapped, session?.startedAt ?? tapped), calendar: calendar)
        case .stop(let goal, let start):
            guard isShown(goal, start) else { return }
            stopFocus(at: max(tapped, start), calendar: calendar)
        case .setPaused(let goal, let start, let paused):
            guard isShown(goal, start), session?.isRunning == paused else { return }
            if paused { pauseFocus(at: max(tapped, session?.runningSince ?? tapped)) } else { resumeFocus(at: tapped) }
        case .quickAdd(let goal):
            quickAdd(to: goal, at: tapped)
        case .startNextBlock:
            guard rest != nil else { return }
            startNextBlock(at: tapped, calendar: calendar)
        case .endRest:
            endRest()
        }
    }
}
