import Foundation
import Testing
@testable import MomentumCore

/// Regressions found in review.
@Suite("Review fixes")
struct ReviewFixTests {
    @Test("Only time goals run focus sessions")
    func focusOnlyOnTimeGoals() {
        let workouts = checkInGoal()
        var data = AppData(goals: [workouts])
        data.startFocus(on: workouts.id, planned: 1500, at: referenceNow, calendar: testCalendar)
        data.toggleFocus(on: workouts.id, at: referenceNow, calendar: testCalendar)
        #expect(data.session == nil)
    }

    @Test("A break taken in the afternoon protects that whole day")
    func breakCoversToday() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        for offset in -5...(-1) { data.log(1, for: goal.id, at: dayOffset(offset)) }
        data.startBreak(for: goal.id, until: referenceNow, at: referenceNow, calendar: testCalendar)
        let stored = data.goal(goal.id)!
        #expect(engine(data).streak(for: stored, now: dayOffset(1)).current == 5)
    }

    @Test("Reading a finished book again keeps the original finish")
    func readAgain() throws {
        let book = Book(title: "Dune", totalPages: 400, currentPage: 400, status: .finished, finishedAt: date(2026, 3, 1))
        let goal = Goal(name: "Read", kind: .books, period: .yearly, target: 12, quickAddStep: 10, books: [book], createdAt: date(2026, 1, 1))
        var data = AppData(goals: [goal])
        data.startReading(book.id, in: goal.id, at: referenceNow)
        let books = try #require(data.goal(goal.id)?.books)
        #expect(books.count == 2)
        let reread = try #require(books.first { $0.status == .reading })
        #expect(reread.currentPage == 0)
        data.quickAdd(to: goal.id, at: referenceNow)
        #expect(data.goal(goal.id)?.books.first { $0.id == reread.id }?.currentPage == 10)
        #expect(engine(data).currentAmount(for: goal, now: referenceNow) == 1)
    }

    @Test("A running session's widget timeline ends within the hour so it gets rebuilt")
    func widgetTimelineRebuilds() {
        let goal = Goal(name: "Focus", kind: .time, target: 3600)
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, planned: 90 * 60, at: referenceNow, calendar: testCalendar)
        let dates = WidgetSchedule.entryDates(for: data, now: referenceNow, calendar: testCalendar)
        #expect(dates.last == referenceNow.addingTimeInterval(55 * 60))
        #expect(!dates.contains(date(2026, 10, 9, 0)))
    }

    @Test("Nudges and the recap don't depend on the goal reminders switch")
    func independentSwitches() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        for offset in -4...(-1) { data.log(1, for: goal.id, at: dayOffset(offset)) }
        data.preferences.remindersEnabled = false
        let planned = ReminderPlanner.plan(engine(data), now: referenceNow)
        #expect(planned.contains { $0.identifier.contains("nudge") })
        #expect(planned.contains { $0.identifier.contains("recap") })
    }

    @Test("A correction on a later day applies to the week's total")
    func crossDayCorrection() {
        let goal = Goal(name: "Pages", kind: .amount, unit: "pages", period: .weekly, target: 100, createdAt: date(2026, 9, 1))
        var data = AppData(goals: [goal])
        data.log(300, for: goal.id, at: date(2026, 10, 5, 9))
        data.log(-270, for: goal.id, at: date(2026, 10, 6, 9))
        let e = engine(data)
        #expect(e.currentAmount(for: goal, now: referenceNow) == 30)
        #expect(e.amount(for: goal, on: date(2026, 10, 6), now: referenceNow) == 0)
    }

    @Test("A young goal's pace uses only the days it has existed")
    func youngPace() throws {
        let goal = Goal(name: "Run", kind: .amount, unit: "km", period: .monthly, target: 100, createdAt: referenceNow)
        var data = AppData(goals: [goal])
        data.log(10, for: goal.id, at: referenceNow)
        let pace = try #require(engine(data).pace(for: goal, now: referenceNow))
        #expect(pace.recentPerDay == 10)
        #expect(pace.status == .onTrack)
    }
}

@Suite("Goal settings")
struct GoalSettingsTests {
    @Test("Applying editor settings keeps milestones, books, links and breaks")
    func applySettingsKeepsContent() {
        var stored = Goal(name: "Old", kind: .milestones, target: 0, milestones: [Milestone(title: "A", completedAt: referenceNow)])
        stored.links = [GoalLink(title: "Doc", url: URL(string: "https://example.com")!)]
        stored.breaks = [DateInterval(start: referenceNow, duration: 86_400)]
        var edited = stored
        edited.name = "New"
        edited.color = .pink
        edited.milestones = [Milestone(title: "A")]   // stale copy from when the sheet opened
        edited.links = []
        stored.applySettings(from: edited)
        #expect(stored.name == "New")
        #expect(stored.color == .pink)
        #expect(stored.milestones.first?.isDone == true)
        #expect(stored.links.count == 1)
        #expect(stored.breaks.count == 1)
    }
}
