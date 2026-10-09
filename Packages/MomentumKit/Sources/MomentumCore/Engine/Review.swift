import Foundation

/// A week looked back on: what got done, how it felt, what went well.
public struct WeekReview: Sendable {
    public struct GoalWeek: Identifiable, Sendable {
        public var goalID: UUID
        /// Days a daily goal's target was met, out of the days it was due; for other goals, 1 of 1
        /// when the period containing the week's last day was met.
        public var met: Int
        public var due: Int
        /// Progress logged during the week, in base units.
        public var amount: Double
        public var id: UUID { goalID }
    }

    public struct Win: Identifiable, Sendable {
        public var day: DayID
        public var text: String
        public var id: DayID { day }
    }

    public var range: DateInterval
    public var focusSeconds: Double
    public var previousFocusSeconds: Double
    public var perfectDays: Int
    public var activeDays: Int
    /// The day with the most due goals met, then the most focus.
    public var bestDay: Date?
    public var goals: [GoalWeek]
    public var wins: [Win]
    public var averageMood: Double?
    /// Achievements earned during the week, oldest first.
    public var achievements: [Achievement]

    /// Focus compared with the week before, as a fraction (0.25 is a quarter more).
    public var focusChange: Double? {
        previousFocusSeconds > 0 ? (focusSeconds - previousFocusSeconds) / previousFocusSeconds : nil
    }
}

extension ProgressEngine {
    /// The seven days ending with `now`'s day.
    public func weekReview(endingAt now: Date) -> WeekReview {
        let end = day(1, from: now)
        let start = day(-6, from: now)
        let previous = DateInterval(start: day(-7, from: start), end: start)
        let range = DateInterval(start: start, end: end)
        let days = (0..<7).map { day($0, from: start) }
        let summaries = days.map { daySummary($0, now: now) }

        let timeGoals = data.goals.filter { $0.kind == .time }
        let focus = timeGoals.reduce(0) { $0 + amount(for: $1, in: range, now: now) }
        let previousFocus = timeGoals.reduce(0) { $0 + amount(for: $1, in: previous, now: now) }

        let best = summaries
            .filter { $0.focusSeconds > 0 || !$0.met.isEmpty }
            .max { ($0.met.count, $0.focusSeconds) < ($1.met.count, $1.focusSeconds) }?.day

        let goals: [WeekReview.GoalWeek] = activeGoals.compactMap { goal in
            let logged = amount(for: goal, in: range, now: now)
            if goal.effectivePeriod == .daily && goal.kind != .milestones && goal.kind != .books {
                let due = summaries.filter { $0.due.contains(goal.id) }.count
                let met = summaries.filter { $0.met.contains(goal.id) }.count
                guard due > 0 || logged > 0 else { return nil }
                return WeekReview.GoalWeek(goalID: goal.id, met: met, due: due, amount: logged)
            }
            guard logged > 0 || hasActivity(goal, during: range) else { return nil }
            return WeekReview.GoalWeek(goalID: goal.id, met: isMet(goal, periodContaining: now, now: now) ? 1 : 0, due: 1, amount: logged)
        }

        let entries = data.journal.filter { range.holds($0.day.date(in: calendar)) }
        let wins = entries.filter { !$0.win.isEmpty }.map { WeekReview.Win(day: $0.day, text: $0.win) }
        let moods = entries.compactMap(\.mood).map { Double($0.rawValue) }

        let earned = data.achievements
            .filter { range.holds($0.value) }
            .sorted { $0.value < $1.value }
            .compactMap { Achievement.with(id: $0.key) }

        return WeekReview(range: range, focusSeconds: focus, previousFocusSeconds: previousFocus,
                          perfectDays: summaries.filter(\.isPerfect).count,
                          activeDays: summaries.filter { !$0.active.isEmpty }.count,
                          bestDay: best, goals: goals, wins: wins,
                          averageMood: moods.isEmpty ? nil : moods.reduce(0, +) / Double(moods.count),
                          achievements: earned)
    }

    private func hasActivity(_ goal: Goal, during range: DateInterval) -> Bool {
        var day = range.start
        while day < range.end {
            if hasActivity(goal, on: day, now: range.end) { return true }
            day = self.day(1, from: day)
        }
        return false
    }

    /// How each day of the year ending with `now`'s day went, oldest first: the share of due
    /// goals met (nil when nothing was due) and the mood, if rated.
    public func yearInPixels(endingAt now: Date) -> [(day: Date, completion: Double?, mood: Mood?)] {
        let first = day(-364, from: now)
        let moods = Dictionary(data.journal.compactMap { entry in entry.mood.map { (entry.day, $0) } }, uniquingKeysWith: { first, _ in first })
        return (0..<365).map { offset in
            let date = day(offset, from: first)
            let summary = daySummary(date, now: now)
            return (date, summary.completion, moods[DayID(date, calendar: calendar)])
        }
    }
}
