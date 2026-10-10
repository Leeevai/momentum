import Foundation
import Testing
@testable import MomentumCore

@Suite("Streaks")
struct StreakTests {
    @Test("An unfinished today keeps the streak; finishing it extends it")
    func todayDoesNotBreak() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        for offset in -3...(-1) { data.log(1, for: goal.id, at: dayOffset(offset)) }
        #expect(engine(data).streak(for: goal, now: referenceNow).current == 3)

        data.log(1, for: goal.id, at: referenceNow)
        let streak = engine(data).streak(for: goal, now: referenceNow)
        #expect(streak.current == 4)
        #expect(streak.best == 4)
        #expect(streak.unit == "day")
    }

    @Test("A missed scheduled day resets the streak but not the best")
    func gapBreaks() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        for offset in [-6, -5, -4, -2, -1] { data.log(1, for: goal.id, at: dayOffset(offset)) }
        let streak = engine(data).streak(for: goal, now: referenceNow)
        #expect(streak.current == 2)
        #expect(streak.best == 3)
    }

    @Test("Unscheduled days are skipped, and count when worked anyway")
    func weekdaysOnly() {
        // Reference Thursday: -3 Mon ... -1 Wed; -5 Sat and -4 Sun are off days.
        let goal = checkInGoal(weekdays: Set(2...6))
        var data = AppData(goals: [goal])
        for offset in [-7, -6, -3, -2, -1] { data.log(1, for: goal.id, at: dayOffset(offset)) }
        #expect(engine(data).streak(for: goal, now: referenceNow).current == 5)

        data.log(1, for: goal.id, at: dayOffset(-4))
        #expect(engine(data).streak(for: goal, now: referenceNow).current == 6)
    }

    @Test("Days inside a break never break the streak")
    func breaksProtect() {
        var goal = checkInGoal()
        goal.breaks = [DateInterval(start: testCalendar.startOfDay(for: dayOffset(-4)), end: testCalendar.startOfDay(for: dayOffset(-2)))]
        var data = AppData(goals: [goal])
        for offset in [-6, -5, -2, -1] { data.log(1, for: goal.id, at: dayOffset(offset)) }
        #expect(engine(data).streak(for: goal, now: referenceNow).current == 4)
    }

    @Test("Weekly goals count consecutive weeks that hit the target")
    func weekly() {
        let goal = checkInGoal(createdDaysAgo: 60, period: .weekly, target: 2)
        var data = AppData(goals: [goal])
        // Two workouts in each of the last three full weeks, one so far this week.
        for weeksAgo in 1...3 {
            data.log(1, for: goal.id, at: dayOffset(-7 * weeksAgo))
            data.log(1, for: goal.id, at: dayOffset(-7 * weeksAgo + 1))
        }
        data.log(1, for: goal.id, at: referenceNow)
        let streak = engine(data).streak(for: goal, now: referenceNow)
        #expect(streak.current == 3)
        #expect(streak.unit == "week")

        data.log(1, for: goal.id, at: referenceNow)
        #expect(engine(data).streak(for: goal, now: referenceNow).current == 4)
    }

    @Test("A log and the correction that takes it back leave the day inactive")
    func cancelledDayInactive() {
        let goal = Goal(name: "Novel", kind: .amount, unit: "words", period: .total, target: 50_000, quickAddStep: 500,
                        createdAt: dayOffset(-10))
        var data = AppData(goals: [goal])
        data.log(500, for: goal.id, at: dayOffset(-4))
        // Nothing written three days ago: 500 words tapped in by mistake, then taken back.
        data.log(500, for: goal.id, at: dayOffset(-3, hour: 9))
        data.log(-500, for: goal.id, at: dayOffset(-3, hour: 10), note: "Correction")
        for offset in -2...(-1) { data.log(500, for: goal.id, at: dayOffset(offset)) }
        let progress = engine(data)
        let streak = progress.streak(for: goal, now: referenceNow)
        let worked = progress.hasActivity(goal, on: dayOffset(-3), now: referenceNow)
        let shade = progress.intensity(for: goal, on: dayOffset(-3), now: referenceNow)
        #expect(streak.current == 2)
        #expect(!worked)
        #expect(shade == 0)
    }

    @Test("Completion rate ignores off days and an unfinished today")
    func completionRate() {
        let goal = checkInGoal(weekdays: Set(2...6), createdDaysAgo: 6)
        var data = AppData(goals: [goal])
        // Due: Fri -6, Mon -3, Tue -2, Wed -1 (today unfinished is not counted).
        data.log(1, for: goal.id, at: dayOffset(-6))
        data.log(1, for: goal.id, at: dayOffset(-2))
        data.log(1, for: goal.id, at: dayOffset(-1))
        let rate = engine(data).completionRate(for: goal, now: referenceNow)
        #expect(rate == 0.75)
    }
}

@Suite("Period sums")
struct PeriodSumTests {
    @Test("Weekly, monthly and yearly sums include exactly the days inside the period")
    func periodBoundaries() {
        let goal = checkInGoal(createdDaysAgo: 400, period: .weekly, target: 10)
        var data = AppData(goals: [goal])
        // Week of Mon 5 Oct ... Sun 11 Oct (weeks start Monday in the test calendar).
        data.log(1, for: goal.id, at: date(2026, 10, 4, 23, 59))  // Sunday before: excluded
        data.log(2, for: goal.id, at: date(2026, 10, 5, 0, 0))    // Monday: included
        data.log(4, for: goal.id, at: date(2026, 10, 8, 9))       // Thursday: included
        data.log(8, for: goal.id, at: date(2026, 10, 1, 9))       // Earlier this month
        data.log(16, for: goal.id, at: date(2025, 12, 31, 9))     // Last year: only in the lifetime total
        let e = engine(data)
        #expect(e.amount(for: goal, in: e.interval(of: .weekly, containing: referenceNow), now: referenceNow) == 6)
        #expect(e.amount(for: goal, in: e.interval(of: .monthly, containing: referenceNow), now: referenceNow) == 15)
        #expect(e.amount(for: goal, in: e.interval(of: .yearly, containing: referenceNow), now: referenceNow) == 15)
        #expect(e.lifetimeAmount(for: goal, now: referenceNow) == 31)
    }

    @Test("A day sum survives a daylight-saving change")
    func dstDay() {
        // Chicago falls back on Sunday 1 November 2026: that day is 25 hours long.
        let goal = checkInGoal(createdDaysAgo: 60)
        var data = AppData(goals: [goal])
        data.log(1, for: goal.id, at: date(2026, 11, 1, 0, 30))
        data.log(1, for: goal.id, at: date(2026, 11, 1, 23, 30))
        data.log(1, for: goal.id, at: date(2026, 11, 2, 0, 30))
        let e = engine(data)
        let later = date(2026, 11, 3)
        #expect(e.amount(for: goal, in: e.dayInterval(date(2026, 11, 1)), now: later) == 2)
        #expect(e.amount(for: goal, on: date(2026, 11, 2), now: later) == 1)
    }
}

@Suite("Streak minimums")
struct StreakMinimumTests {
    @Test("A day that reaches only the minimum keeps the streak but isn't complete")
    func minimumKeepsStreak() {
        var goal = Goal(name: "Deep work", kind: .time, target: 2 * 3600, streakMinimum: 20 * 60, createdAt: dayOffset(-3))
        var data = AppData(goals: [goal])
        data.log(2 * 3600, for: goal.id, at: dayOffset(-3))
        data.log(25 * 60, for: goal.id, at: dayOffset(-2))  // a hard day: only the minimum
        data.log(2 * 3600, for: goal.id, at: dayOffset(-1))
        data.log(25 * 60, for: goal.id, at: referenceNow)
        let e = engine(data)
        #expect(e.streak(for: goal, now: referenceNow).current == 4)
        #expect(!e.isComplete(goal, now: referenceNow))
        #expect(e.completionRate(for: goal, now: referenceNow) == 2.0 / 3.0)

        goal.streakMinimum = nil
        data.upsert(goal)
        #expect(engine(data).streak(for: goal, now: referenceNow).current == 1)
    }

    @Test("A minimum above the target is capped at the target")
    func cappedAtTarget() {
        let goal = Goal(name: "Gym", kind: .count, target: 1, streakMinimum: 5)
        #expect(engine(AppData(goals: [goal])).streakThreshold(for: goal) == 1)
    }

    @Test("Older files without a minimum decode as none")
    func decodesWithoutMinimum() throws {
        let json = #"{"version": 2, "goals": [{"name": "Old", "kind": "time", "target": 600}]}"#
        let goal = try #require(FileStore.decode(Data(json.utf8)).goals.first)
        #expect(goal.streakMinimum == nil)
    }
}
