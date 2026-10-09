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

    public static func plan(_ engine: ProgressEngine, now: Date, days: Int = 7, limit: Int = 60) -> [PlannedReminder] {
        guard engine.data.preferences.remindersEnabled else { return [] }
        let calendar = engine.calendar
        var planned = streakNudges(engine, now: now)
        for goal in engine.activeGoals {
            guard let reminder = goal.reminder, reminder.isEnabled else { continue }
            let streak = engine.streak(for: goal, now: now)
            for offset in 0..<days {
                let day = engine.day(offset, from: now)
                guard let fire = calendar.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: day),
                      fire > now,
                      engine.isScheduled(goal, on: day),
                      !goal.isOnBreak(at: fire) else { continue }
                let inCurrentPeriod = engine.interval(of: goal.effectivePeriod, containing: now).contains(fire)
                if inCurrentPeriod && engine.isComplete(goal, now: now) { continue }
                planned.append(PlannedReminder(
                    identifier: "\(identifierPrefix)\(goal.id.uuidString).\(engine.dayKey(day))",
                    goalID: goal.id,
                    fireDate: fire,
                    title: "\(goal.icon) \(goal.name)",
                    body: body(for: goal, engine: engine, streak: streak, isToday: offset == 0, now: now)
                ))
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
        guard let fire = calendar.date(byAdding: .minute, value: preferences.streakNudgeMinute, to: today), fire > now else { return [] }
        let tomorrow = engine.day(1, from: now)
        return engine.activeGoals.compactMap { goal in
            guard goal.kind != .milestones, goal.kind != .books, goal.effectivePeriod != .total,
                  !goal.isOnBreak(at: fire), !engine.isComplete(goal, now: now) else { return nil }
            // Only the period's last day puts the streak at risk tonight.
            let period = engine.interval(of: goal.effectivePeriod, containing: now)
            guard period.end <= tomorrow, engine.isRequired(goal, on: today) || goal.effectivePeriod != .daily else { return nil }
            let streak = engine.streak(for: goal, now: now)
            guard streak.current >= 2 else { return nil }
            let done = engine.currentAmount(for: goal, now: now)
            let left = goal.format(max(0, engine.target(for: goal) - done))
            return PlannedReminder(
                identifier: "\(identifierPrefix)nudge.\(goal.id.uuidString).\(engine.dayKey(today))",
                goalID: goal.id,
                fireDate: fire,
                title: "\(goal.icon) Your \(Goal.streakText(streak.current, unit: streak.unit)) ends at midnight",
                body: "\(left) of \(goal.name) to go. You've got this."
            )
        }
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
