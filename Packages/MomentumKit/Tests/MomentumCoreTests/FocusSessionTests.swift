import Foundation
import Testing
@testable import MomentumCore

@Suite("Focus sessions")
struct FocusSessionTests {
    let goal = Goal(name: "Focus", kind: .time, target: 30 * 60, createdAt: date(2026, 9, 1))

    @Test("A running session counts live toward today")
    func liveProgress() {
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, at: date(2026, 10, 8, 14), calendar: testCalendar)
        let now = date(2026, 10, 8, 14, 20)
        #expect(engine(data).amount(for: goal, on: now, now: now) == 20 * 60)
        #expect(!engine(data).isComplete(goal, now: now))
        #expect(engine(data).isComplete(goal, now: date(2026, 10, 8, 14, 30)))
    }

    @Test("Paused time is not counted")
    func pauseExcludesTime() {
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, at: date(2026, 10, 8, 9), calendar: testCalendar)
        data.pauseFocus(at: date(2026, 10, 8, 9, 10))
        data.resumeFocus(at: date(2026, 10, 8, 9, 40))
        let entries = data.stopFocus(at: date(2026, 10, 8, 9, 45), calendar: testCalendar)
        #expect(entries.count == 1)
        #expect(entries.first?.amount == 900.0)
        #expect(entries.first?.source == .timer)
        #expect(data.session == nil)
    }

    @Test("A session across midnight credits both days")
    func splitsAtMidnight() {
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, at: date(2026, 10, 7, 23, 40), calendar: testCalendar)
        data.stopFocus(at: date(2026, 10, 8, 0, 25), calendar: testCalendar)
        let e = engine(data)
        #expect(e.amount(for: goal, on: date(2026, 10, 7), now: referenceNow) == 20 * 60)
        #expect(e.amount(for: goal, on: date(2026, 10, 8), now: referenceNow) == 25 * 60)
    }

    @Test("Starting a new session saves the one already running")
    func startStopsPrevious() {
        let other = Goal(name: "Other", kind: .time, target: 600)
        var data = AppData(goals: [goal, other])
        data.startFocus(on: goal.id, at: date(2026, 10, 8, 10), calendar: testCalendar)
        data.startFocus(on: other.id, at: date(2026, 10, 8, 10, 30), calendar: testCalendar)
        #expect(data.session?.goalID == other.id)
        #expect(data.entries.map(\.amount) == [1800.0])
    }

    @Test("Planned sessions report their end and remaining time, accounting for pauses")
    func plannedEnd() throws {
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, planned: 25 * 60, at: date(2026, 10, 8, 10), calendar: testCalendar)
        data.pauseFocus(at: date(2026, 10, 8, 10, 10))
        data.resumeFocus(at: date(2026, 10, 8, 10, 20))
        let session = try #require(data.session)
        #expect(session.plannedEnd == date(2026, 10, 8, 10, 35))
        #expect(session.remaining(at: date(2026, 10, 8, 10, 30)) == 300.0)
        #expect(session.counterReferenceDate == date(2026, 10, 8, 10, 10))
    }

    @Test("Toggle uses the goal's default focus length")
    func toggleUsesDefaultLength() {
        var pomodoro = goal
        pomodoro.focusMinutes = 25
        var data = AppData(goals: [pomodoro])
        data.toggleFocus(on: pomodoro.id, at: referenceNow, calendar: testCalendar)
        #expect(data.session?.plannedDuration == 1500.0)
        data.toggleFocus(on: pomodoro.id, at: referenceNow.addingTimeInterval(60), calendar: testCalendar)
        #expect(data.session == nil)
        #expect(data.entries.count == 1)
    }

    @Test("Negative corrections never take a day below zero")
    func correctionsClamp() {
        var data = AppData(goals: [goal])
        data.log(600, for: goal.id, at: referenceNow)
        data.log(-1200, for: goal.id, at: referenceNow)
        #expect(engine(data).amount(for: goal, on: referenceNow, now: referenceNow) == 0)
    }
}
