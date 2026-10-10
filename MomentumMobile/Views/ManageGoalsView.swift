import MomentumCore
import SwiftUI

/// Every goal in one list, from Settings: drag to set the order Today and the widgets follow,
/// archive what's on hold, and bring archived goals back.
struct ManageGoalsView: View {
    @Environment(GoalStore.self) private var store
    @State private var deleting: Goal?

    var body: some View {
        let engine = store.engine
        List {
            Section {
                ForEach(engine.activeGoals) { goal in
                    row(goal)
                        .swipeActions {
                            Button("Archive", systemImage: "archivebox") { store.archive(goal) }
                                .tint(.attention)
                        }
                }
                .onMove { source, destination in
                    store.reorder(engine.activeGoals, from: source, to: destination)
                }
            } header: {
                Text("Goals")
            } footer: {
                Text("Tap Edit to drag them into order; Today and the widgets follow it. Swipe to archive.")
            }
            if !engine.archivedGoals.isEmpty {
                Section {
                    ForEach(engine.archivedGoals) { goal in
                        HStack {
                            row(goal)
                                .opacity(0.6)
                            Button("Restore") { store.unarchive(goal) }
                                .buttonStyle(.borderless)
                                .font(.callout.weight(.semibold))
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = goal }
                        }
                    }
                } header: {
                    Text("Archived")
                } footer: {
                    Text("Archived goals keep their history. Restore one to bring it back to Today.")
                }
            }
        }
        .navigationTitle("Goals")
        .toolbar { EditButton() }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "goal")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { goal in
            Button("Delete Goal", role: .destructive) { store.delete(goal) }
        } message: { _ in
            Text("This removes the goal and all of its history.")
        }
    }

    private func row(_ goal: Goal) -> some View {
        HStack(spacing: 12) {
            GoalIcon(goal: goal, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name)
                    .font(.body.weight(.medium))
                Text(goal.targetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
