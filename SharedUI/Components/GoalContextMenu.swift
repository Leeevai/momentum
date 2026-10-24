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
        let targets = store.combineTargets(for: goal)
        if !targets.isEmpty {
            // Two goals can share a name (the same goal made on two devices): the target tells them apart.
            Menu("Combine Into") {
                ForEach(targets) { target in
                    Button("\(target.name) — \(target.targetDescription)") {
                        store.confirmingCombine = GoalCombination(source: goal, target: target)
                    }
                }
            }
        }
        if goal.supportsChallenge || goal.challenge != nil {
            Menu(goal.challenge == nil ? "Start a Challenge" : "Challenge") {
                ChallengeMenu(goal: goal)
            }
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
