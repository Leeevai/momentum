import Foundation

/// How a goal's challenge is going, day by day.
public struct ChallengeStatus: Equatable, Sendable {
    public enum Day: Equatable, Sendable {
        /// The goal was kept.
        case kept
        /// Due, and not kept.
        case missed
        /// Not due: a day off or a break.
        case free
        /// Today, due and not kept yet.
        case today
        case upcoming
    }

    public let challenge: Challenge
    /// One per day of the challenge, in order.
    public let days: [Day]

    /// Which day of the challenge today is, from 1; 0 before it starts, and its length after.
    public let dayNumber: Int

    public var kept: Int { days.count { $0 == .kept } }
    public var missed: Int { days.count { $0 == .missed } }
    /// Days still to play, today included while it isn't kept.
    public var remaining: Int { days.count { $0 == .today || $0 == .upcoming } }
    public var isFinished: Bool { remaining == 0 }
    /// Finished without a miss, with at least one day kept (a challenge spent entirely on a
    /// break isn't won).
    public var isWon: Bool { isFinished && missed == 0 && kept > 0 }
    /// Kept or free so far: no day missed.
    public var isOnTrack: Bool { missed == 0 }
    /// The share of the challenge behind it.
    public var fraction: Double { Double(days.count - remaining) / Double(max(days.count, 1)) }
    /// The share of days kept or free: what a ring fills with, so a won challenge with days off
    /// still closes.
    public var keptFraction: Double { Double(kept + days.count { $0 == .free }) / Double(max(days.count, 1)) }
}

extension ProgressEngine {
    /// The state of `goal`'s challenge, if it has one.
    public func challengeStatus(for goal: Goal, now: Date) -> ChallengeStatus? {
        guard let challenge = goal.challenge, challenge.days > 0 else { return nil }
        let first = startOfDay(challenge.start.date(in: calendar))
        let today = dayKey(now)
        var days: [ChallengeStatus.Day] = []
        days.reserveCapacity(challenge.days)
        for offset in 0..<challenge.days {
            let date = day(offset, from: first)
            let key = dayKey(date)
            if key > today {
                days.append(.upcoming)
                continue
            }
            let isKept = isKept(goal, on: date, now: now)
            if isKept {
                days.append(.kept)
            } else if !isRequired(goal, on: date) {
                days.append(.free)
            } else {
                days.append(key == today ? .today : .missed)
            }
        }
        let elapsed = DayMath.days(fromKey: today) - DayMath.days(fromKey: dayKey(first)) + 1
        return ChallengeStatus(challenge: challenge, days: days, dayNumber: min(max(elapsed, 0), challenge.days))
    }

    /// Whether a challenge day counts as kept: the daily target (or its streak minimum) for a daily
    /// goal, and any progress for the others, which have no target of their own for a day.
    private func isKept(_ goal: Goal, on date: Date, now: Date) -> Bool {
        goal.effectivePeriod == .daily
            ? keepsStreak(goal, periodContaining: date, now: now)
            : hasActivity(goal, on: date, now: now)
    }
}

extension AppData {
    /// Starts a challenge on a goal from `day`, replacing any it had.
    public mutating func startChallenge(on goalID: UUID, days: Int, from day: DayID) {
        updateGoal(goalID) { $0.challenge = Challenge(start: day, days: days) }
    }

    public mutating func endChallenge(on goalID: UUID) {
        updateGoal(goalID) { $0.challenge = nil }
    }
}
