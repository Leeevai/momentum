import Foundation

/// Aggregates across all goals for the Insights screen.
public struct InsightsReport: Sendable {
    public struct FocusDay: Identifiable, Hashable, Sendable {
        public var day: Date
        public var goalID: UUID
        public var seconds: Double
        public var id: String { "\(goalID.uuidString)-\(day.timeIntervalSince1970)" }
    }

    public struct GoalScore: Identifiable, Hashable, Sendable {
        public var goalID: UUID
        public var completion: Double?
        public var streak: Int
        public var bestStreak: Int
        public var streakUnit: String
        public var id: UUID { goalID }
    }

    public struct CategoryShare: Identifiable, Hashable, Sendable {
        public var name: String
        public var seconds: Double
        public var id: String { name }
    }

    public struct Bucket: Identifiable, Hashable, Sendable {
        /// Weekday (1 = Sunday ... 7) or hour of day (0...23).
        public var index: Int
        public var seconds: Double
        public var id: Int { index }
    }

    public var range: DateInterval
    public var days: Int
    public var focusByDay: [FocusDay]
    public var totalFocusSeconds: Double
    public var activeDays: Int
    public var loggedEntries: Int
    public var milestonesCompleted: Int
    public var booksFinished: Int
    public var pagesRead: Double
    public var scores: [GoalScore]
    public var focusByWeekday: [Bucket]
    public var focusByHour: [Bucket]
    /// The same measures over the equally long range just before this one.
    /// Focus time by goal category, largest first; uncategorized goals share "Other".
    public var focusByCategory: [CategoryShare]
    public var previousFocusSeconds: Double
    public var previousActiveDays: Int

    /// Relative change in focus time against the previous range, or nil without a baseline.
    public var focusChange: Double? {
        previousFocusSeconds > 0 ? totalFocusSeconds / previousFocusSeconds - 1 : nil
    }

    /// Average focus per day over the range.
    public var averageFocusPerDay: Double { days > 0 ? totalFocusSeconds / Double(days) : 0 }

    /// The hour with the most focus, if any.
    public var peakHour: Int? { focusByHour.filter { $0.seconds > 0 }.max { $0.seconds < $1.seconds }?.index }
}

extension ProgressEngine {
    public func insights(days: Int, now: Date) -> InsightsReport {
        let start = day(-(days - 1), from: now)
        let range = DateInterval(start: start, end: day(1, from: now))
        let timeGoals = data.goals.filter { $0.kind == .time }

        var focusByDay: [InsightsReport.FocusDay] = []
        var weekday = [Int: Double]()
        var categories = [String: Double]()
        var total = 0.0
        for goal in timeGoals {
            for daily in dailyAmounts(for: goal, days: days, now: now) where daily.amount > 0 {
                focusByDay.append(.init(day: daily.day, goalID: goal.id, seconds: daily.amount))
                weekday[calendar.component(.weekday, from: daily.day), default: 0] += daily.amount
                categories[goal.category.isEmpty ? "Other" : goal.category, default: 0] += daily.amount
                total += daily.amount
            }
        }

        var hours = [Int: Double]()
        let timeGoalIDs = Set(timeGoals.map(\.id))
        let rangeEntries = data.entries.filter { range.holds($0.date) }
        for entry in rangeEntries where timeGoalIDs.contains(entry.goalID) && entry.amount > 0 {
            spread(entry, into: &hours)
        }

        var active = Set<Int>()
        for entry in rangeEntries where entry.amount > 0 { active.insert(dayKey(entry.date)) }
        var milestones = 0
        var books = 0
        for goal in data.goals {
            for milestone in goal.milestones {
                if let done = milestone.completedAt, range.holds(done) {
                    milestones += 1
                    active.insert(dayKey(done))
                }
            }
            books += booksFinished(for: goal, in: range)
        }
        let bookGoalIDs = Set(data.goals.filter { $0.kind == .books }.map(\.id))
        let pages = rangeEntries
            .filter { bookGoalIDs.contains($0.goalID) }
            .reduce(0) { $0 + $1.amount }

        let previousRange = DateInterval(start: day(-days, from: start), end: start)
        var previousFocus = 0.0
        for goal in timeGoals {
            previousFocus += amount(for: goal, in: previousRange, now: now)
        }
        let previousActive = Set(data.entries.filter { previousRange.holds($0.date) && $0.amount > 0 }.map { dayKey($0.date) }).count

        let scores = activeGoals.map { goal in
            let streak = streak(for: goal, now: now)
            return InsightsReport.GoalScore(goalID: goal.id, completion: completionRate(for: goal, now: now), streak: streak.current, bestStreak: streak.best, streakUnit: streak.unit)
        }

        return InsightsReport(
            range: range,
            days: days,
            focusByDay: focusByDay,
            totalFocusSeconds: total,
            activeDays: active.count,
            loggedEntries: rangeEntries.count,
            milestonesCompleted: milestones,
            booksFinished: books,
            pagesRead: max(0, pages),
            scores: scores,
            focusByWeekday: (1...7).map { .init(index: $0, seconds: weekday[$0] ?? 0) },
            focusByHour: (0..<24).map { .init(index: $0, seconds: hours[$0] ?? 0) },
            focusByCategory: categories.map { InsightsReport.CategoryShare(name: $0.key, seconds: $0.value) }
                .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name },
            previousFocusSeconds: previousFocus,
            previousActiveDays: previousActive
        )
    }

    /// Spreads a timed entry across the clock hours it covered, starting at its start time.
    private func spread(_ entry: LogEntry, into hours: inout [Int: Double]) {
        var cursor = entry.date
        var remaining = entry.amount
        while remaining > 0 {
            let hour = calendar.component(.hour, from: cursor)
            let nextHour = calendar.dateInterval(of: .hour, for: cursor)?.end ?? cursor.addingTimeInterval(3600)
            let chunk = min(remaining, nextHour.timeIntervalSince(cursor))
            guard chunk > 0 else { break }
            hours[hour, default: 0] += chunk
            remaining -= chunk
            cursor = nextHour
        }
    }
}
