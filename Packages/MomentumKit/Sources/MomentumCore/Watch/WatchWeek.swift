import Foundation

/// The last seven days, worked out on the iPhone for the watch's Week page: a few hundred bytes.
public struct WatchWeek: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        /// The day's start.
        public var date: Date
        /// The daily goals due that day, and how many of them were met.
        public var due: Int
        public var met: Int
        /// Seconds focused that day, on every goal.
        public var focus: Double

        public init(date: Date, due: Int, met: Int, focus: Double) {
            self.date = date
            self.due = due
            self.met = met
            self.focus = focus
        }
    }

    /// A goal's time this week.
    public struct Focus: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var symbol: String
        public var color: GoalColor
        public var seconds: Double

        public init(id: UUID, name: String, symbol: String, color: GoalColor, seconds: Double) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.color = color
            self.seconds = seconds
        }
    }

    /// Oldest first; the last is today.
    public var days: [Day]
    /// Seconds focused in these seven days, and in the seven before them.
    public var focus: Double
    public var previousFocus: Double
    /// Days with anything logged.
    public var activeDays: Int
    /// The longest streak running now, of any goal.
    public var longestStreak: Int
    /// The goals focused on most, most first; at most three.
    public var topGoals: [Focus]

    public init(days: [Day], focus: Double, previousFocus: Double, activeDays: Int, longestStreak: Int, topGoals: [Focus]) {
        self.days = days
        self.focus = focus
        self.previousFocus = previousFocus
        self.activeDays = activeDays
        self.longestStreak = longestStreak
        self.topGoals = topGoals
    }

    /// The daily goals met this week, of those due.
    public var met: Int { days.reduce(0) { $0 + $1.met } }
    public var due: Int { days.reduce(0) { $0 + $1.due } }
}

extension ProgressEngine {
    /// The last seven days, today included. A daily goal counts as due on the days it's scheduled
    /// since it began, outside its breaks; other periods don't fit in a day and aren't counted.
    public func watchWeek(now: Date) -> WatchWeek {
        let goals = activeGoals
        let timed = goals.filter { $0.kind == .time }
        let daily = goals.filter { $0.effectivePeriod == .daily }
        var days: [WatchWeek.Day] = []
        var activeDays = 0
        for offset in -6...0 {
            let date = day(offset, from: now)
            let due = daily.filter { firstDay(of: $0) <= date && isRequired($0, on: date) }
            let met = due.filter { isMet($0, periodContaining: date, now: now) }.count
            let focus = timed.reduce(0.0) { $0 + amount(for: $1, on: date, now: now) }
            days.append(WatchWeek.Day(date: date, due: due.count, met: met, focus: focus))
            if goals.contains(where: { hasActivity($0, on: date, now: now) }) { activeDays += 1 }
        }
        let week = DateInterval(start: day(-6, from: now), end: day(1, from: now))
        let before = DateInterval(start: day(-13, from: now), end: week.start)
        let focused: [WatchWeek.Focus] = timed.compactMap { goal in
            let seconds = amount(for: goal, in: week, now: now)
            guard seconds > 0 else { return nil }
            return WatchWeek.Focus(id: goal.id, name: goal.name, symbol: goal.symbol, color: goal.color, seconds: seconds)
        }
        let top = focused.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
        let focus = days.reduce(0.0) { $0 + $1.focus }
        let previousFocus = timed.reduce(0.0) { $0 + amount(for: $1, in: before, now: now) }
        return WatchWeek(days: days, focus: focus, previousFocus: previousFocus, activeDays: activeDays,
                         longestStreak: longestCurrentStreak(now: now), topGoals: Array(top.prefix(3)))
    }
}
