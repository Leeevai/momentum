import Foundation
import Testing
@testable import MomentumCore

@Suite("Undo patches")
struct DataPatchTests {
    @Test("Undo removes what the action logged, and keeps what happened after")
    func undoKeepsLaterChanges() {
        let gym = checkInGoal()
        let focus = Goal(name: "Focus", kind: .time, target: 3600)
        var data = AppData(goals: [gym, focus])

        let before = data
        data.log(1, for: gym.id, at: referenceNow)
        let patch = DataPatch(from: before, to: data)

        // Later, a widget runs a whole session on another goal.
        data.startFocus(on: focus.id, at: referenceNow, calendar: testCalendar)
        data.stopFocus(at: referenceNow.addingTimeInterval(3300), calendar: testCalendar)

        patch.undo(on: &data)
        #expect(data.entries.filter { $0.goalID == gym.id }.isEmpty)
        #expect(data.entries.filter { $0.goalID == focus.id }.map(\.amount) == [3300])
    }

    @Test("Undoing a delete brings the goal and its history back in place; redo deletes again")
    func undoDelete() {
        let first = checkInGoal()
        let second = Goal(name: "Second", target: 60)
        let third = Goal(name: "Third", target: 60)
        var data = AppData(goals: [first, second, third])
        data.log(1, for: second.id, at: referenceNow)

        let before = data
        data.deleteGoal(second.id)
        let patch = DataPatch(from: before, to: data)

        patch.undo(on: &data)
        #expect(data.goals.map(\.id) == [first.id, second.id, third.id])
        #expect(data.entries.count == 1)

        patch.reversed.undo(on: &data)
        #expect(data.goals.map(\.id) == [first.id, third.id])
        #expect(data.entries.isEmpty)
    }

    @Test("Undoing a stop doesn't override a session started since")
    func sessionConflict() {
        let a = Goal(name: "A", kind: .time, target: 600)
        let b = Goal(name: "B", kind: .time, target: 600)
        var data = AppData(goals: [a, b])
        data.startFocus(on: a.id, at: referenceNow, calendar: testCalendar)

        let before = data
        data.stopFocus(at: referenceNow.addingTimeInterval(600), calendar: testCalendar)
        let patch = DataPatch(from: before, to: data)

        data.startFocus(on: b.id, at: referenceNow.addingTimeInterval(700), calendar: testCalendar)
        patch.undo(on: &data)
        #expect(data.session?.goalID == b.id)
        #expect(data.entries.isEmpty)
    }

    @Test("Reorders undo, and an action that changed nothing is empty")
    func reorder() {
        let goals = ["A", "B", "C"].map { Goal(name: $0, target: 1) }
        var data = AppData(goals: goals)
        #expect(DataPatch(from: data, to: data).isEmpty)

        let before = data
        data.moveGoals(fromOffsets: IndexSet([0]), toOffset: 3)
        let patch = DataPatch(from: before, to: data)
        patch.undo(on: &data)
        #expect(data.goals.map(\.name) == ["A", "B", "C"])
    }
}
