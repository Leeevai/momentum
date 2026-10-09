import MomentumCore
import SwiftUI

/// Actions offered when right-clicking a goal anywhere.
struct GoalContextMenu: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        if goal.kind == .time {
            Button(store.engine.isRunning(goal) ? "Stop Focus" : "Start Focus") { store.toggleFocus(goal) }
        }
        Button("Log Progress…") { store.sheet = .log(goalID: goal.id) }
            .disabled(goal.kind == .milestones || goal.kind == .books)
        Divider()
        Button("Edit…") { store.sheet = .editGoal(goal) }
        Button("Share Progress…") { store.sheet = .share(goal) }
        Button("Duplicate") { store.duplicate(goal) }
        Menu(goal.challenge == nil ? "Start a Challenge" : "Challenge") {
            ChallengeMenu(goal: goal)
        }
        if goal.isOnBreak(at: .now) {
            Button("End Break") { store.endBreak(goal) }
        } else {
            Menu("Take a Break") {
                Button("Until Tomorrow") { store.startBreak(goal, until: .now) }
                Button("For a Week") { store.startBreak(goal, until: Calendar.current.date(byAdding: .day, value: 6, to: .now)) }
                Button("Until I Resume") { store.startBreak(goal, until: nil) }
            }
        }
        Divider()
        if goal.isArchived {
            Button("Restore") { store.unarchive(goal) }
        } else {
            Button("Archive") { store.archive(goal) }
        }
        Button("Delete…", role: .destructive) { store.confirmingDelete = goal }
    }
}
