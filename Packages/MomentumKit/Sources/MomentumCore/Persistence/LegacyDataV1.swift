import Foundation

/// The first data format (Momentum 0.1): daily goals only, progress kept as per-day totals.
struct LegacyDataV1: Decodable {
    struct Goal: Decodable {
        var id: UUID
        var name: String
        var emoji: String
        var color: GoalColor
        var kind: String
        var dailyTarget: Int
        var weekdays: Set<Int>
        var createdAt: Date
    }

    struct Session: Decodable {
        var goalID: UUID
        var startedAt: Date
    }

    var goals: [Goal]
    var progress: [String: [String: Int]]
    var session: Session?

    /// Converts to the current format: each stored day total becomes one log entry at noon.
    func migrated(calendar: Calendar = .current) -> AppData {
        let goals = goals.map { old -> MomentumCore.Goal in
            let isTimed = old.kind == "timed"
            return MomentumCore.Goal(
                id: old.id,
                name: old.name,
                icon: old.emoji,
                color: old.color,
                kind: isTimed ? .time : .count,
                unit: isTimed ? "" : "check-ins",
                period: .daily,
                target: Double(isTimed ? old.dailyTarget * 60 : old.dailyTarget),
                weekdays: old.weekdays,
                createdAt: old.createdAt
            )
        }
        let timedGoals = Set(self.goals.filter { $0.kind == "timed" }.map(\.id))
        var entries: [LogEntry] = []
        for (goalKey, days) in progress {
            guard let goalID = UUID(uuidString: goalKey) else { continue }
            for (dayKey, amount) in days {
                guard amount > 0, let day = Self.date(fromDayKey: dayKey, calendar: calendar) else { continue }
                entries.append(LogEntry(goalID: goalID, date: day, amount: Double(amount), source: timedGoals.contains(goalID) ? .timer : .manual))
            }
        }
        entries.sort { $0.date < $1.date }
        let session = session.map { FocusSession(goalID: $0.goalID, start: $0.startedAt) }
        return AppData(goals: goals, entries: entries, session: session)
    }

    /// Noon on the "yyyy-MM-dd" day, clear of any DST transition.
    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
