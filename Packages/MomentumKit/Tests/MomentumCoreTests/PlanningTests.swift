import Foundation
import Testing
@testable import MomentumCore

@Suite("Reminders, pace and formatting")
struct PlanningTests {
    func remindedGoal(weekdays: Set<Int> = Set(1...7)) -> Goal {
        var goal = checkInGoal(weekdays: weekdays)
        goal.reminder = ReminderSchedule(hour: 18, minute: 0)
        return goal
    }

    @Test("Reminders skip today once the goal is done")
    func skipsCompletedToday() {
        let goal = remindedGoal()
        var data = AppData(goals: [goal])
        let pending = ReminderPlanner.plan(engine(data), now: referenceNow, days: 3)
        #expect(pending.count == 3)
        #expect(pending.first?.fireDate == date(2026, 10, 8, 18))

        data.log(1, for: goal.id, at: referenceNow)
        let afterDone = ReminderPlanner.plan(engine(data), now: referenceNow, days: 3)
        #expect(afterDone.map(\.fireDate) == [date(2026, 10, 9, 18), date(2026, 10, 10, 18)])
    }

    @Test("Reminders skip unscheduled days, breaks, and the global switch")
    func skipsOffDays() {
        // Thursday reference: Fri due, Sat/Sun off for a weekdays goal.
        var goal = remindedGoal(weekdays: Set(2...6))
        var data = AppData(goals: [goal])
        let plan = ReminderPlanner.plan(engine(data), now: referenceNow, days: 4)
        #expect(plan.map(\.fireDate) == [date(2026, 10, 8, 18), date(2026, 10, 9, 18)])

        goal.breaks = [DateInterval(start: referenceNow, end: date(2026, 10, 9, 23))]
        data.upsert(goal)
        #expect(ReminderPlanner.plan(engine(data), now: referenceNow, days: 4).isEmpty)

        data.preferences.remindersEnabled = false
        #expect(ReminderPlanner.plan(engine(data), now: referenceNow, days: 4).isEmpty)
    }

    @Test("Pace compares the recent rate with what the deadline needs")
    func pace() throws {
        var goal = Goal(name: "Novel", kind: .amount, unit: "words", period: .total, target: 10_000,
                        deadline: date(2026, 10, 28), createdAt: date(2026, 9, 1))
        var data = AppData(goals: [goal])
        for offset in -13...0 { data.log(500, for: goal.id, at: dayOffset(offset)) }
        // 7,000 written, 3,000 left; 500 a day finishes in 6 days, well before the deadline.
        let onTrack = try #require(engine(data).pace(for: goal, now: referenceNow))
        #expect(onTrack.status == .onTrack)
        #expect(onTrack.remaining == 3000)
        #expect(onTrack.daysLeft == 20)

        goal.target = 30_000
        data.upsert(goal)
        let behind = try #require(engine(data).pace(for: goal, now: referenceNow))
        #expect(behind.status == .behind)
        #expect(behind.neededPerDay == 23_000.0 / 20)
    }

    @Test("Durations, units and progress read naturally")
    func formatting() {
        #expect(Formatting.duration(0) == "0m")
        #expect(Formatting.duration(30) == "<1m")
        #expect(Formatting.duration(45 * 60) == "45m")
        #expect(Formatting.duration(90 * 60) == "1h 30m")
        #expect(Formatting.duration(2 * 3600) == "2h")
        #expect(Formatting.clock(3725) == "1:02:05")
        #expect(Formatting.unit("pages", for: 1) == "page")
        #expect(Formatting.unit("glasses", for: 1) == "glass")
        #expect(Formatting.unit("stories", for: 1) == "story")
        #expect(Formatting.unit("pages", for: 2) == "pages")

        let workouts = Goal(name: "Gym", kind: .count, unit: "workouts", period: .weekly, target: 4)
        #expect(workouts.targetDescription == "4 workouts a week")
        #expect(workouts.format(1) == "1 workout")
        #expect(workouts.progressText(2, target: 4) == "2 / 4 workouts")

        let books = Goal(name: "Read", kind: .books, period: .yearly, target: 24)
        #expect(books.targetDescription == "24 books a year")
        #expect(books.format(1) == "1 book")
    }

    @Test("Today's list holds what is due, plus anything already worked on")
    func todayList() {
        let weekdays = checkInGoal(weekdays: Set(2...6))
        let weekends = checkInGoal(weekdays: [1, 7])
        var archived = checkInGoal()
        archived.archivedAt = referenceNow
        var data = AppData(goals: [weekdays, weekends, archived])
        #expect(engine(data).todayGoals(now: referenceNow).map(\.id) == [weekdays.id])

        data.log(1, for: weekends.id, at: referenceNow)
        #expect(Set(engine(data).todayGoals(now: referenceNow).map(\.id)) == [weekdays.id, weekends.id])
    }

    @Test("Demo data produces a believable report")
    func demoInsights() {
        let data = AppData.demo(now: referenceNow, calendar: testCalendar)
        let e = engine(data)
        let report = e.insights(days: 30, now: referenceNow)
        #expect(report.totalFocusSeconds > 0)
        #expect(report.activeDays > 20)
        #expect(report.scores.count == data.goals.count)
        #expect(e.longestCurrentStreak(now: referenceNow) > 0)
        #expect(data.goals.first { $0.kind == .books }?.currentBook?.title == "Dune")
    }
}
