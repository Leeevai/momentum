import Foundation

/// A badge earned for something worth marking: a streak, focus hours, books, a perfect week.
///
/// Most are measured from history, so they are earned whenever the numbers get there, whichever
/// device or widget logged the progress. A few mark events that history doesn't keep (finishing a
/// whole Pomodoro cycle) and are recorded when they happen.
public struct Achievement: Identifiable, Hashable, Sendable {
    public enum Tier: Int, Comparable, Sendable, CaseIterable {
        case bronze, silver, gold, platinum

        public var title: String {
            switch self {
            case .bronze: "Bronze"
            case .silver: "Silver"
            case .gold: "Gold"
            case .platinum: "Platinum"
            }
        }

        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Family: String, CaseIterable, Sendable {
        case consistency, streaks, focus, reading, milestones, journal, craft

        public var title: String {
            switch self {
            case .consistency: "Consistency"
            case .streaks: "Streaks"
            case .focus: "Focus"
            case .reading: "Reading"
            case .milestones: "Projects"
            case .journal: "Journal"
            case .craft: "Craft"
            }
        }

        public var symbolName: String {
            switch self {
            case .consistency: "leaf.fill"
            case .streaks: "flame.fill"
            case .focus: "timer"
            case .reading: "books.vertical.fill"
            case .milestones: "flag.checkered"
            case .journal: "book.closed.fill"
            case .craft: "wand.and.stars"
            }
        }
    }

    /// What an achievement measures.
    public enum Metric: Hashable, Sendable {
        case anyProgress
        case activeDays
        case perfectDays
        case perfectRun
        case comeback
        case dailyStreak
        case weeklyStreak
        case focusHours
        case longestSessionMinutes
        case bestWeekFocusHours
        case earlyBird
        case nightOwl
        case booksFinished
        case pagesRead
        case milestonesCompleted
        case goalsFinished
        case journalReflections
        case journalPlans
        case activeGoals
        case habitStack
        /// Recorded by the action itself, not measured.
        case event
    }

    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let tier: Tier
    public let family: Family
    public let metric: Metric
    public let target: Double

    public static let fullCycleID = "pomodoro-cycle"
}

/// An achievement with how far along it is.
public struct AchievementProgress: Identifiable, Hashable, Sendable {
    public let achievement: Achievement
    public let value: Double
    public let earnedAt: Date?

    public var id: String { achievement.id }
    public var isEarned: Bool { earnedAt != nil }
    public var fraction: Double { isEarned ? 1 : min(1, max(0, value / max(achievement.target, 1))) }
}

extension Achievement {
    /// Every achievement, in display order within each family.
    public static let all: [Achievement] = [
        // Consistency
        .init(id: "first-step", title: "First Step", detail: "Log progress on any goal.", symbol: "figure.walk", tier: .bronze, family: .consistency, metric: .anyProgress, target: 1),
        .init(id: "active-7", title: "Showing Up", detail: "Make progress on 7 different days.", symbol: "calendar.badge.checkmark", tier: .bronze, family: .consistency, metric: .activeDays, target: 7),
        .init(id: "active-30", title: "Habit Formed", detail: "Make progress on 30 different days.", symbol: "leaf.fill", tier: .silver, family: .consistency, metric: .activeDays, target: 30),
        .init(id: "active-100", title: "Rooted", detail: "Make progress on 100 different days.", symbol: "tree.fill", tier: .gold, family: .consistency, metric: .activeDays, target: 100),
        .init(id: "active-365", title: "Evergreen", detail: "Make progress on 365 different days.", symbol: "mountain.2.fill", tier: .platinum, family: .consistency, metric: .activeDays, target: 365),
        .init(id: "perfect-day", title: "Perfect Day", detail: "Finish every goal due on a day.", symbol: "star.fill", tier: .bronze, family: .consistency, metric: .perfectDays, target: 1),
        .init(id: "perfect-10", title: "Ten Perfect Days", detail: "Have 10 days with every goal finished.", symbol: "star.circle.fill", tier: .silver, family: .consistency, metric: .perfectDays, target: 10),
        .init(id: "perfect-week", title: "Flawless Week", detail: "Finish every due goal 7 days in a row.", symbol: "sparkles", tier: .gold, family: .consistency, metric: .perfectRun, target: 7),
        .init(id: "comeback", title: "Comeback", detail: "Return to a goal after a week or more away.", symbol: "arrow.uturn.backward.circle.fill", tier: .silver, family: .consistency, metric: .comeback, target: 1),

        // Streaks
        .init(id: "streak-3", title: "Warming Up", detail: "Keep a daily streak for 3 days.", symbol: "flame", tier: .bronze, family: .streaks, metric: .dailyStreak, target: 3),
        .init(id: "streak-7", title: "On Fire", detail: "Keep a daily streak for a week.", symbol: "flame.fill", tier: .silver, family: .streaks, metric: .dailyStreak, target: 7),
        .init(id: "streak-30", title: "Unstoppable", detail: "Keep a daily streak for 30 days.", symbol: "bolt.fill", tier: .gold, family: .streaks, metric: .dailyStreak, target: 30),
        .init(id: "streak-100", title: "Centurion", detail: "Keep a daily streak for 100 days.", symbol: "crown.fill", tier: .platinum, family: .streaks, metric: .dailyStreak, target: 100),
        .init(id: "streak-365", title: "Year of Momentum", detail: "Keep a daily streak for a whole year.", symbol: "sun.max.fill", tier: .platinum, family: .streaks, metric: .dailyStreak, target: 365),
        .init(id: "weeks-4", title: "Steady Rhythm", detail: "Hit a weekly goal 4 weeks running.", symbol: "metronome.fill", tier: .silver, family: .streaks, metric: .weeklyStreak, target: 4),
        .init(id: "weeks-12", title: "Quarter Strong", detail: "Hit a weekly goal 12 weeks running.", symbol: "chart.line.uptrend.xyaxis", tier: .gold, family: .streaks, metric: .weeklyStreak, target: 12),

        // Focus
        .init(id: "focus-1", title: "First Hour", detail: "Focus for an hour in total.", symbol: "hourglass", tier: .bronze, family: .focus, metric: .focusHours, target: 1),
        .init(id: "focus-10", title: "Ten Hours In", detail: "Focus for 10 hours in total.", symbol: "timer", tier: .bronze, family: .focus, metric: .focusHours, target: 10),
        .init(id: "focus-100", title: "Hundred Club", detail: "Focus for 100 hours in total.", symbol: "clock.badge.checkmark.fill", tier: .gold, family: .focus, metric: .focusHours, target: 100),
        .init(id: "focus-1000", title: "Mastery Path", detail: "Focus for 1,000 hours in total.", symbol: "graduationcap.fill", tier: .platinum, family: .focus, metric: .focusHours, target: 1000),
        .init(id: "session-90", title: "Deep Diver", detail: "Focus for 90 minutes in one session.", symbol: "water.waves", tier: .silver, family: .focus, metric: .longestSessionMinutes, target: 90),
        .init(id: "session-180", title: "Flow State", detail: "Focus for 3 hours in one session.", symbol: "infinity", tier: .gold, family: .focus, metric: .longestSessionMinutes, target: 180),
        .init(id: "week-20", title: "Marathon Week", detail: "Focus for 20 hours in one week.", symbol: "figure.run", tier: .gold, family: .focus, metric: .bestWeekFocusHours, target: 20),
        .init(id: fullCycleID, title: "Full Cycle", detail: "Finish a whole Pomodoro cycle, up to the long break.", symbol: "arrow.2.circlepath", tier: .silver, family: .focus, metric: .event, target: 1),
        .init(id: "early-bird", title: "Early Bird", detail: "Start a focus session before 7 in the morning.", symbol: "sunrise.fill", tier: .bronze, family: .focus, metric: .earlyBird, target: 1),
        .init(id: "night-owl", title: "Night Owl", detail: "Start a focus session after 11 at night.", symbol: "moon.stars.fill", tier: .bronze, family: .focus, metric: .nightOwl, target: 1),

        // Reading
        .init(id: "book-1", title: "Bookworm", detail: "Finish a book.", symbol: "book.closed.fill", tier: .bronze, family: .reading, metric: .booksFinished, target: 1),
        .init(id: "book-10", title: "Shelf Builder", detail: "Finish 10 books.", symbol: "books.vertical.fill", tier: .silver, family: .reading, metric: .booksFinished, target: 10),
        .init(id: "book-50", title: "Librarian", detail: "Finish 50 books.", symbol: "building.columns.fill", tier: .platinum, family: .reading, metric: .booksFinished, target: 50),
        .init(id: "pages-1000", title: "Page Turner", detail: "Read 1,000 pages.", symbol: "book.pages.fill", tier: .silver, family: .reading, metric: .pagesRead, target: 1000),
        .init(id: "pages-10000", title: "Ten Thousand Pages", detail: "Read 10,000 pages.", symbol: "text.book.closed.fill", tier: .gold, family: .reading, metric: .pagesRead, target: 10000),

        // Projects
        .init(id: "milestone-1", title: "First Flag", detail: "Complete a milestone.", symbol: "flag.fill", tier: .bronze, family: .milestones, metric: .milestonesCompleted, target: 1),
        .init(id: "milestone-25", title: "Trailblazer", detail: "Complete 25 milestones.", symbol: "flag.checkered", tier: .silver, family: .milestones, metric: .milestonesCompleted, target: 25),
        .init(id: "summit", title: "Summit", detail: "Reach an overall goal or finish a project.", symbol: "mountain.2.fill", tier: .gold, family: .milestones, metric: .goalsFinished, target: 1),

        // Journal
        .init(id: "journal-1", title: "Dear Diary", detail: "Reflect on a day.", symbol: "square.and.pencil", tier: .bronze, family: .journal, metric: .journalReflections, target: 1),
        .init(id: "journal-7", title: "Reflective", detail: "Reflect on 7 days.", symbol: "text.quote", tier: .silver, family: .journal, metric: .journalReflections, target: 7),
        .init(id: "journal-30", title: "Self-Aware", detail: "Reflect on 30 days.", symbol: "brain.head.profile", tier: .gold, family: .journal, metric: .journalReflections, target: 30),
        .init(id: "plan-7", title: "Planner", detail: "Plan 7 days with an intention or priorities.", symbol: "list.bullet.clipboard.fill", tier: .silver, family: .journal, metric: .journalPlans, target: 7),

        // Craft
        .init(id: "goals-3", title: "Juggler", detail: "Keep 3 goals going at once.", symbol: "circle.grid.3x3.fill", tier: .bronze, family: .craft, metric: .activeGoals, target: 3),
        .init(id: "stack", title: "Habit Stacker", detail: "Stack one goal after another.", symbol: "square.stack.3d.up.fill", tier: .bronze, family: .craft, metric: .habitStack, target: 1),
    ]

    public static func with(id: String) -> Achievement? {
        all.first { $0.id == id }
    }
}

// MARK: - Measuring

extension ProgressEngine {
    /// Every achievement with its progress, in display order.
    public func achievements(now: Date) -> [AchievementProgress] {
        var stats = AchievementStats(engine: self, now: now)
        return Achievement.all.map { achievement in
            let earned = data.achievements[achievement.id]
            // Earned achievements don't need measuring; reading everything is the slow part.
            let value = earned != nil ? achievement.target : stats.value(of: achievement.metric)
            return AchievementProgress(achievement: achievement, value: value, earnedAt: earned)
        }
    }

    /// Achievements reached that aren't recorded as earned yet.
    public func newlyEarnedAchievements(now: Date) -> [Achievement] {
        var stats = AchievementStats(engine: self, now: now)
        return Achievement.all.filter { achievement in
            guard data.achievements[achievement.id] == nil, achievement.metric != .event else { return false }
            return stats.value(of: achievement.metric) >= achievement.target
        }
    }
}

extension AppData {
    /// Records achievements reached, returning those newly earned.
    @discardableResult
    public mutating func recordAchievements(now: Date = .now, calendar: Calendar = .current) -> [Achievement] {
        let earned = ProgressEngine(data: self, calendar: calendar).newlyEarnedAchievements(now: now)
        for achievement in earned { achievements[achievement.id] = now }
        return earned
    }
}

/// The numbers achievements are measured by, each computed on first use.
struct AchievementStats {
    let engine: ProgressEngine
    let now: Date
    private var cache: [Achievement.Metric: Double] = [:]

    init(engine: ProgressEngine, now: Date) {
        self.engine = engine
        self.now = now
    }

    mutating func value(of metric: Achievement.Metric) -> Double {
        if let cached = cache[metric] { return cached }
        let value = compute(metric)
        cache[metric] = value
        return value
    }

    private var data: AppData { engine.data }
    private var calendar: Calendar { engine.calendar }

    private func compute(_ metric: Achievement.Metric) -> Double {
        switch metric {
        case .anyProgress:
            let finished = data.goals.contains { goal in
                goal.milestones.contains(where: \.isDone) || goal.books.contains { $0.finishedAt != nil }
            }
            return data.entries.contains { $0.amount > 0 } || finished ? 1 : 0
        case .activeDays:
            return Double(activeDayKeys.count)
        case .perfectDays:
            return Double(perfectDays.count)
        case .perfectRun:
            return Double(longestPerfectRun)
        case .comeback:
            return hasComeback ? 1 : 0
        case .dailyStreak:
            return Double(bestStreak(unit: "day"))
        case .weeklyStreak:
            return Double(bestStreak(unit: "week"))
        case .focusHours:
            return max(0, timeGoalIDs.reduce(0) { $0 + (engine.dailyTotals[$1]?.values.reduce(0, +) ?? 0) }) / 3600
        case .longestSessionMinutes:
            return (data.entries.filter { $0.source == .timer }.map(\.amount).max() ?? 0) / 60
        case .bestWeekFocusHours:
            var weeks: [Int: Double] = [:]
            for id in timeGoalIDs {
                for (key, seconds) in engine.dailyTotals[id] ?? [:] {
                    let day = DayMath.days(fromKey: key)
                    let weekStart = day - (DayMath.weekday(day) - calendar.firstWeekday + 7) % 7
                    weeks[weekStart, default: 0] += seconds
                }
            }
            return (weeks.values.max() ?? 0) / 3600
        case .earlyBird:
            return sessionStartHours.contains { (4..<7).contains($0) } ? 1 : 0
        case .nightOwl:
            return sessionStartHours.contains { $0 >= 23 || $0 < 4 } ? 1 : 0
        case .booksFinished:
            return Double(data.goals.reduce(0) { $0 + $1.books.filter { $0.finishedAt != nil }.count })
        case .pagesRead:
            let bookGoals = data.goals.filter { $0.kind == .books }.map(\.id)
            return max(0, bookGoals.reduce(0) { $0 + (engine.dailyTotals[$1]?.values.reduce(0, +) ?? 0) })
        case .milestonesCompleted:
            return Double(data.goals.reduce(0) { $0 + $1.milestones.filter(\.isDone).count })
        case .goalsFinished:
            return Double(data.goals.filter { goal in
                (goal.kind == .milestones || goal.effectivePeriod == .total) && engine.isComplete(goal, now: now)
            }.count)
        case .journalReflections:
            return Double(data.journal.filter(\.hasReflection).count)
        case .journalPlans:
            return Double(data.journal.filter(\.hasPlan).count)
        case .activeGoals:
            return Double(engine.activeGoals.count)
        case .habitStack:
            let ids = Set(data.goals.map(\.id))
            return data.goals.contains { $0.stackAfter.map(ids.contains) ?? false } ? 1 : 0
        case .event:
            return 0
        }
    }

    private var timeGoalIDs: Set<UUID> { Set(data.goals.filter { $0.kind == .time }.map(\.id)) }

    private var sessionStartHours: [Int] {
        let zone = calendar.timeZone
        return data.entries.filter { $0.source == .timer && $0.amount >= 60 }.map { DayMath.localHour($0.date, zone) }
    }

    private func bestStreak(unit: String) -> Int {
        data.goals.map { engine.streak(for: $0, now: now) }.filter { $0.unit == unit }.map(\.best).max() ?? 0
    }

    /// Day keys with any progress logged or anything finished.
    private var activeDayKeys: Set<Int> {
        engine.activityDays.values.reduce(into: Set<Int>()) { $0.formUnion($1) }
    }

    /// Whether any goal saw progress again after 7 or more days without any.
    private var hasComeback: Bool {
        engine.activityDays.values.contains { keys in
            let days = keys.map(DayMath.days(fromKey:)).sorted()
            return zip(days, days.dropFirst()).contains { earlier, later in later - earlier >= 8 }
        }
    }

    /// Past days (and today, once done) on which every daily goal due was finished, oldest first.
    /// Only daily goals decide it: a weekly target isn't due on any one day.
    private var perfectDays: [Date] {
        let daily = data.goals.filter { $0.effectivePeriod == .daily && $0.kind != .milestones && $0.kind != .books }
        guard let first = daily.map({ engine.firstDay(of: $0) }).min() else { return [] }
        let today = engine.startOfDay(now)
        var day = max(first, engine.day(-730, from: today))
        var result: [Date] = []
        while day <= today {
            let due = daily.filter { goal in
                engine.isRequired(goal, on: day) && engine.firstDay(of: goal) <= day
                    && (goal.archivedAt.map { $0 > day } ?? true)
            }
            if !due.isEmpty && due.allSatisfy({ engine.isMet($0, periodContaining: day, now: now) }) {
                result.append(day)
            }
            day = engine.day(1, from: day)
        }
        return result
    }

    private var longestPerfectRun: Int {
        var best = 0
        var run = 0
        var previous: Date?
        for day in perfectDays {
            if let previous, engine.day(1, from: previous) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }
}
