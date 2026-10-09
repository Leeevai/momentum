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

    @Test("Undoing a stop doesn't override a session started since, and keeps the stopped time")
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
        #expect(data.entries.map(\.amount) == [600])
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

    @Test("Undoing a switch of timers after pausing keeps the first timer's time")
    func undoStartAfterPause() {
        let a = Goal(name: "A", kind: .time, target: 3600)
        let b = Goal(name: "B", kind: .time, target: 3600)
        var data = AppData(goals: [a, b])
        data.startFocus(on: a.id, at: referenceNow, calendar: testCalendar)

        let before = data
        data.startFocus(on: b.id, at: referenceNow.addingTimeInterval(2400), calendar: testCalendar)
        let patch = DataPatch(from: before, to: data)

        data.pauseFocus(at: referenceNow.addingTimeInterval(2500))   // the same session, paused
        patch.undo(on: &data)
        #expect(data.session?.goalID == a.id)
        #expect(data.entries.isEmpty)

        // And when a different session took over meanwhile, A's 40 minutes stay logged.
        var other = before
        other.startFocus(on: b.id, at: referenceNow.addingTimeInterval(2400), calendar: testCalendar)
        let switchPatch = DataPatch(from: before, to: other)
        other.stopFocus(at: referenceNow.addingTimeInterval(2600), calendar: testCalendar)
        other.startFocus(on: b.id, at: referenceNow.addingTimeInterval(2700), calendar: testCalendar)
        switchPatch.undo(on: &other)
        #expect(other.entries.filter { $0.goalID == a.id }.map(\.amount) == [2400])
    }

    @Test("Undo reverts only the bookmark change it made, not a later one from a widget")
    func undoKeepsLaterGoalChanges() throws {
        let book = Book(title: "Dune", totalPages: 400, currentPage: 100, status: .reading)
        let other = Book(title: "Next", totalPages: 200)
        let goal = Goal(name: "Read", kind: .books, period: .yearly, target: 12, quickAddStep: 10, books: [book, other], createdAt: date(2026, 1, 1))
        var data = AppData(goals: [goal])

        let before = data
        data.logPages(10, in: other.id, of: goal.id, at: referenceNow)       // the action: another book
        let patch = DataPatch(from: before, to: data)

        data.logPages(10, in: book.id, of: goal.id, at: referenceNow)        // later, from a widget
        patch.undo(on: &data)
        let books = try #require(data.goal(goal.id)?.books)
        #expect(books.first { $0.id == book.id }?.currentPage == 110)
        #expect(books.first { $0.id == other.id }?.currentPage == 0)
        #expect(data.entries.map(\.bookID) == [book.id])
    }

    @Test("Undo keeps a milestone completed after an edit it reverts")
    func undoEditKeepsMilestone() throws {
        let goal = Goal(name: "Ship", kind: .milestones, target: 0, milestones: [Milestone(title: "A"), Milestone(title: "B")])
        var data = AppData(goals: [goal])

        let before = data
        data.updateGoal(goal.id) { $0.name = "Ship it" }
        let patch = DataPatch(from: before, to: data)

        data.completeNextMilestone(in: goal.id, at: referenceNow)
        patch.undo(on: &data)
        let stored = try #require(data.goal(goal.id))
        #expect(stored.name == "Ship")
        #expect(stored.milestones.first?.isDone == true)
    }

    @Test("Undoing an added goal removes the session and logs started on it since")
    func undoAddGoalCleansUp() {
        var data = AppData()
        let before = data
        let goal = Goal(name: "Deep work", kind: .time, target: 3600)
        data.upsert(goal)
        let patch = DataPatch(from: before, to: data)

        data.startFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        data.log(60, for: goal.id, at: referenceNow)
        patch.undo(on: &data)
        #expect(data.goals.isEmpty)
        #expect(data.session == nil)
        #expect(data.entries.isEmpty)
    }

    @Test("Undoing a delete brings back the goal's running session")
    func undoDeleteRestoresSession() {
        let goal = Goal(name: "Deep work", kind: .time, target: 3600)
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        let before = data
        data.deleteGoal(goal.id)
        let patch = DataPatch(from: before, to: data)
        patch.undo(on: &data)
        #expect(data.session?.goalID == goal.id)
    }
}
