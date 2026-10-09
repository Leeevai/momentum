import Foundation
import Testing
@testable import MomentumCore

@Suite("Pomodoro")
struct PomodoroTests {
    private func pomodoroData(_ goal: Goal, autoStart: Bool = false) -> AppData {
        var data = AppData(goals: [goal])
        data.preferences.pomodoro = PomodoroSettings(isEnabled: true, shortBreakMinutes: 5, longBreakMinutes: 15, blocksPerCycle: 2,
                                                     autoStartsNextBlock: autoStart)
        return data
    }

    @Test("A finished block logs exactly its length and starts a break, however late it is noticed")
    func blockCompletes() throws {
        let goal = timeGoal()
        var data = pomodoroData(goal)
        data.toggleFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        #expect(data.advancePomodoro(at: referenceNow.addingTimeInterval(10 * 60), calendar: testCalendar) == nil)
        let late = referenceNow.addingTimeInterval(3 * 3600)
        let event = data.advancePomodoro(at: late, calendar: testCalendar)
        let rest = try #require(data.rest)
        #expect(event == .blockCompleted(goalID: goal.id, rest: rest))
        #expect(data.session == nil)
        #expect(data.entries.map(\.amount) == [1500.0])
        #expect(rest.start == referenceNow.addingTimeInterval(1500))
        #expect(rest.duration == 300.0)
        #expect(!rest.isLong)
        #expect(rest.nextBlock == 2)
    }

    @Test("The last block of a cycle earns a long break, then the count starts over")
    func longBreak() throws {
        let goal = timeGoal()
        var data = pomodoroData(goal)
        data.toggleFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        data.advancePomodoro(at: referenceNow.addingTimeInterval(1500), calendar: testCalendar)
        data.startNextBlock(at: referenceNow.addingTimeInterval(1800), calendar: testCalendar)
        #expect(data.session?.block == 2)
        data.advancePomodoro(at: referenceNow.addingTimeInterval(3300), calendar: testCalendar)
        let rest = try #require(data.rest)
        #expect(rest.isLong)
        #expect(rest.duration == 900.0)
        #expect(rest.nextBlock == 1)
        #expect(data.achievements[Achievement.fullCycleID] == referenceNow.addingTimeInterval(3300))
    }

    @Test("A paused block never completes on its own")
    func pausedBlock() {
        let goal = timeGoal()
        var data = pomodoroData(goal)
        data.toggleFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        data.pauseFocus(at: referenceNow.addingTimeInterval(60))
        #expect(data.advancePomodoro(at: referenceNow.addingTimeInterval(3600), calendar: testCalendar) == nil)
        #expect(data.session != nil)
    }

    @Test("The next block starts by itself only right after the break")
    func autoStart() {
        let goal = timeGoal()
        var data = pomodoroData(goal, autoStart: true)
        data.toggleFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        data.advancePomodoro(at: referenceNow.addingTimeInterval(1500), calendar: testCalendar)
        var asleep = data
        let breakEnd = referenceNow.addingTimeInterval(1800)
        #expect(data.advancePomodoro(at: breakEnd.addingTimeInterval(30), calendar: testCalendar) == .blockStarted(goalID: goal.id, block: 2))
        #expect(data.session?.startedAt == breakEnd)
        #expect(asleep.advancePomodoro(at: breakEnd.addingTimeInterval(3600), calendar: testCalendar) == nil)
        #expect(asleep.session == nil)
        #expect(asleep.rest != nil)
    }

    @Test("Starting another goal during a break ends the break and starts a fresh cycle")
    func otherGoalEndsBreak() {
        let goal = timeGoal()
        let other = Goal(name: "Spanish", kind: .time, target: 1800)
        var data = pomodoroData(goal)
        data.goals.append(other)
        data.toggleFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        data.advancePomodoro(at: referenceNow.addingTimeInterval(1500), calendar: testCalendar)
        data.toggleFocus(on: other.id, at: referenceNow.addingTimeInterval(1600), calendar: testCalendar)
        #expect(data.rest == nil)
        #expect(data.session?.block == 1)
        #expect(data.session?.plannedDuration == 1500.0)
    }

    @Test("Open-ended goals run default-length blocks with Pomodoro on")
    func defaultLength() {
        let goal = timeGoal(minutes: nil)
        var data = pomodoroData(goal)
        data.preferences.defaultFocusMinutes = 50
        #expect(data.defaultFocusLength(for: goal.id) == 3000.0)
        data.preferences.pomodoro.isEnabled = false
        #expect(data.defaultFocusLength(for: goal.id) == nil)
    }

    @Test("Undoing the start of the next block brings the break back")
    func undoNextBlock() {
        let goal = timeGoal()
        var data = pomodoroData(goal)
        data.toggleFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        data.advancePomodoro(at: referenceNow.addingTimeInterval(1500), calendar: testCalendar)
        let before = data
        data.startNextBlock(at: referenceNow.addingTimeInterval(1700), calendar: testCalendar)
        DataPatch(from: before, to: data).undo(on: &data)
        #expect(data.session == nil)
        #expect(data.rest == before.rest)
    }
}
