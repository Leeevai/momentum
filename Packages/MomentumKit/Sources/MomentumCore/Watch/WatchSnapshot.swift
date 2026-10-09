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

    public init(items: [Item] = [], session: FocusSession? = nil, rest: RestPeriod? = nil, done: Int = 0, total: Int = 0, generatedAt: Date = .distantPast) {
        self.items = items
        self.session = session
        self.rest = rest
        self.done = done
        self.total = total
        self.generatedAt = generatedAt
    }

    /// The most goals sent: a watch screen's worth, and then some.
    public static let itemLimit = 12

    public func item(_ id: UUID) -> Item? { items.first { $0.id == id } }
}

/// Something done on the watch, carried out on the iPhone.
public enum WatchAction: Codable, Equatable, Sendable {
    case toggleFocus(goal: UUID)
    case togglePause
    case stopFocus
    case quickAdd(goal: UUID)
    case startNextBlock
    case endRest
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
        return WatchSnapshot(items: items, session: data.session, rest: data.rest, done: summary.done, total: summary.total, generatedAt: now)
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
    /// Carries out an action from the watch.
    public mutating func apply(_ action: WatchAction, at now: Date = .now, calendar: Calendar = .current) {
        switch action {
        case .toggleFocus(let goal):
            guard self.goal(goal)?.kind == .time else { return }
            toggleFocus(on: goal, at: now, calendar: calendar)
        case .togglePause: togglePauseFocus(at: now)
        case .stopFocus: stopFocus(at: now, calendar: calendar)
        case .quickAdd(let goal): quickAdd(to: goal, at: now)
        case .startNextBlock: startNextBlock(at: now, calendar: calendar)
        case .endRest: endRest()
        }
    }
}
