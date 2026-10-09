import Foundation
import Testing
@testable import MomentumCore

@Suite("Challenges")
struct ChallengeTests {
    private func data(_ goal: Goal, days: Int, from offset: Int, kept: [Int]) -> AppData {
        var data = AppData(goals: [goal])
        data.startChallenge(on: goal.id, days: days, from: DayID(dayOffset(offset), calendar: testCalendar))
        for day in kept { data.log(1, for: goal.id, at: dayOffset(day)) }
        return data
    }

    /// The challenge status of the goal as stored in `data`.
    private func status(_ data: AppData, _ goal: Goal) -> ChallengeStatus? {
        let engine = engine(data)
        return engine.goal(goal.id).flatMap { engine.challengeStatus(for: $0, now: referenceNow) }
    }

    @Test("Each day is kept, missed, today or still to come")
    func days() throws {
        let goal = checkInGoal()
        let status = try #require(status(data(goal, days: 7, from: -3, kept: [-3, -2]), goal))
        #expect(status.days == [.kept, .kept, .missed, .today, .upcoming, .upcoming, .upcoming])
        #expect(status.dayNumber == 4)
        #expect(status.kept == 2)
        #expect(status.missed == 1)
        #expect(status.remaining == 4)
        #expect(!status.isOnTrack)
        #expect(!status.isFinished)
    }

    @Test("Days off are free, and progress on one still counts")
    func daysOff() throws {
        // Weekdays only; the challenge runs Friday to Thursday.
        let goal = checkInGoal(weekdays: Set(2...6))
        let status = try #require(status(data(goal, days: 7, from: -6, kept: [-6, -4, -3, -2, -1, 0]), goal))
        #expect(status.days == [.kept, .free, .kept, .kept, .kept, .kept, .kept])
        #expect(status.isFinished)
        #expect(status.isWon)
    }

    @Test("The last day isn't over until it's kept or past")
    func lastDay() throws {
        let goal = checkInGoal()
        var data = data(goal, days: 3, from: -2, kept: [-2, -1])
        let pending = try #require(status(data, goal))
        #expect(!pending.isFinished)
        #expect(pending.isOnTrack)
        data.log(1, for: goal.id, at: referenceNow)
        let won = try #require(status(data, goal))
        #expect(won.isWon)
        #expect(won.dayNumber == 3)
    }

    @Test("A challenge that starts later is all to come")
    func future() throws {
        let goal = checkInGoal()
        let status = try #require(status(data(goal, days: 7, from: 1, kept: []), goal))
        #expect(status.dayNumber == 0)
        #expect(status.days.allSatisfy { $0 == .upcoming })
    }

    @Test("Winning a week-long challenge earns its award, not the longer ones")
    func award() {
        let goal = checkInGoal()
        let data = data(goal, days: 7, from: -6, kept: Array(-6...0))
        let earned = Set(engine(data).newlyEarnedAchievements(now: referenceNow).map(\.id))
        #expect(earned.contains("challenge-7"))
        #expect(!earned.contains("challenge-30"))
    }

    @Test("A missed day loses the award")
    func lostAward() {
        let goal = checkInGoal()
        let data = data(goal, days: 7, from: -7, kept: [-7, -6, -5, -3, -2, -1])
        let earned = Set(engine(data).newlyEarnedAchievements(now: referenceNow).map(\.id))
        #expect(!earned.contains("challenge-7"))
    }

    @Test("A challenge survives saving, and goals without one still load")
    func coding() throws {
        var goal = checkInGoal()
        goal.challenge = Challenge(start: DayID(year: 2026, month: 10, day: 1), days: 30)
        let decoded = try DateCoding.decoder().decode(Goal.self, from: DateCoding.encoder().encode(goal))
        #expect(decoded.challenge == goal.challenge)

        goal.challenge = nil
        let plain = try DateCoding.decoder().decode(Goal.self, from: DateCoding.encoder().encode(goal))
        #expect(plain.challenge == nil)
    }
}
