import Foundation

/// A notification Momentum should have scheduled.
public struct PlannedReminder: Hashable, Sendable {
    public var identifier: String
    public var goalID: UUID
    public var fireDate: Date
    public var title: String
    public var body: String
}

/// Works out the upcoming goal reminders.
///
/// Notifications cannot check a condition when they fire, so instead of a repeating trigger the
/// app schedules one-off reminders for the next few days and replans whenever data changes.
/// That lets a reminder skip a day the goal is already done, or one it is not due.
public enum ReminderPlanner {
    public static let identifierPrefix = "reminder."

    /// Goal reminders, streak nudges and the weekly recap, each behind its own switch.
    public static func plan(_ engine: ProgressEngine, now: Date, days: Int = 7, limit: Int = 60) -> [PlannedReminder] {
        let calendar = engine.calendar
        var planned = streakNudges(engine, now: now)
        planned += weeklyRecap(engine, now: now).map { [$0] } ?? []
        let goalsWithReminders = engine.data.preferences.remindersEnabled ? engine.activeGoals : []
        for goal in goalsWithReminders {
            guard let reminder = goal.reminder, reminder.isEnabled else { continue }
            let streak = engine.streak(for: goal, now: now)
            let current = engine.interval(of: goal.effectivePeriod, containing: now)
            let doneThisPeriod = engine.isComplete(goal, now: now)
            for offset in 0..<days {
                let day = engine.day(offset, from: now)
                guard engine.isScheduled(goal, on: day) else { continue }
                for minute in reminder.times {
                    guard let fire = wallClock(minute, on: day, calendar: calendar),
                          fire > now,
                          !goal.isOnBreak(at: fire) else { continue }
                    // Half-open: the next period starts exactly at this one's end.
                    if doneThisPeriod && fire >= current.start && fire < current.end { continue }
                    planned.append(PlannedReminder(
                        identifier: "\(identifierPrefix)\(goal.id.uuidString).\(engine.dayKey(day)).\(minute)",
                        goalID: goal.id,
                        fireDate: fire,
                        title: "\(goal.icon) \(goal.name)",
                        body: body(for: goal, engine: engine, streak: streak, isToday: offset == 0, now: now)
                    ))
                }
            }
        }
        return Array(planned.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    /// Tonight's "your streak ends at midnight" nudges: for each goal whose streak is at least two
    /// periods long and would break if the current period ended unmet tonight.
    static func streakNudges(_ engine: ProgressEngine, now: Date) -> [PlannedReminder] {
        let preferences = engine.data.preferences
        guard preferences.streakNudgesEnabled else { return [] }
        let calendar = engine.calendar
        let today = engine.startOfDay(now)
        guard let fire = wallClock(preferences.streakNudgeMinute, on: today, calendar: calendar), fire > now else { return [] }
        let tomorrow = engine.day(1, from: now)
        return engine.activeGoals.compactMap { goal in
            guard goal.kind != .milestones, goal.kind != .books, goal.effectivePeriod != .total,
                  !goal.isOnBreak(at: fire), !engine.keepsStreak(goal, periodContaining: now, now: now) else { return nil }
            // Only the period's last day puts the streak at risk tonight.
            let period = engine.interval(of: goal.effectivePeriod, containing: now)
            guard period.end <= tomorrow, engine.isRequired(goal, on: today) || goal.effectivePeriod != .daily else { return nil }
            let streak = engine.streak(for: goal, now: now)
            guard streak.current >= 2 else { return nil }
            let done = engine.currentAmount(for: goal, now: now)
            let left = goal.format(max(0, engine.streakThreshold(for: goal) - done))
            return PlannedReminder(
                identifier: "\(identifierPrefix)nudge.\(goal.id.uuidString).\(engine.dayKey(today))",
                goalID: goal.id,
                fireDate: fire,
                title: "\(goal.icon) Your \(Goal.streakText(streak.current, unit: streak.unit)) ends at midnight",
                body: "\(left) of \(goal.name) to go. You've got this."
            )
        }
    }

    /// A summary on the last evening of the week, an hour after the streak-nudge time.
    static func weeklyRecap(_ engine: ProgressEngine, now: Date) -> PlannedReminder? {
        let preferences = engine.data.preferences
        guard preferences.weeklyRecapEnabled, let anyGoal = engine.activeGoals.first else { return nil }
        let week = engine.interval(of: .weekly, containing: now)
        let lastDay = engine.day(-1, from: week.end)
        let minute = min(23 * 60, preferences.streakNudgeMinute + 60)
        guard let fire = wallClock(minute, on: lastDay, calendar: engine.calendar), fire > now else { return nil }

        let report = engine.insights(days: 7, now: now)
        let scores = engine.activeGoals.compactMap { engine.isOnTargetThisWeek($0, now: now) }
        var parts: [String] = []
        if report.totalFocusSeconds > 0 { parts.append("\(Formatting.duration(report.totalFocusSeconds)) focused") }
        parts.append("active \(report.activeDays) of 7 days")
        if !scores.isEmpty { parts.append("\(scores.filter { $0 }.count) of \(scores.count) goals on target") }
        let best = engine.longestCurrentStreak(now: now)
        if best > 1 { parts.append("best streak \(best)") }
        let summary = parts.joined(separator: " · ")
        return PlannedReminder(
            identifier: "\(identifierPrefix)recap.\(engine.dayKey(lastDay))",
            goalID: anyGoal.id,
            fireDate: fire,
            title: "Your week in Momentum",
            body: summary.prefix(1).uppercased() + summary.dropFirst() + "."
        )
    }

    /// The time `minute` minutes after midnight on the clock, which on a daylight-saving day is
    /// not the same as adding minutes to the start of the day.
    static func wallClock(_ minute: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
    }

    private static func body(for goal: Goal, engine: ProgressEngine, streak: ProgressEngine.Streak, isToday: Bool, now: Date) -> String {
        let streakLine = streak.current > 1 ? " Keep your \(Goal.streakText(streak.current, unit: streak.unit)) going." : ""
        if isToday {
            let done = engine.currentAmount(for: goal, now: now)
            if done > 0 {
                let progress = goal.progressText(done, target: engine.target(for: goal))
                return "\(progress) \(goal.effectivePeriod.currentLabel.lowercased()).\(streakLine)"
            }
        }
        switch goal.kind {
        case .books:
            if let book = goal.currentBook { return "Time to read \(book.title).\(streakLine)" }
            return "Time to pick up a book.\(streakLine)"
        case .milestones:
            if let next = goal.milestones.first(where: { !$0.isDone }) { return "Next up: \(next.title).\(streakLine)" }
            return "Time to make progress.\(streakLine)"
        case .time, .count, .amount:
            return "Goal: \(goal.targetDescription).\(streakLine)"
        }
    }
}
