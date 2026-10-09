import MomentumCore
import SwiftUI

struct MilestonesSection: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    /// Shows only an "Add milestones" affordance until the first one exists.
    var collapsedWhenEmpty = false
    @State private var newTitle = ""
    @State private var isExpanded = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if collapsedWhenEmpty && goal.milestones.isEmpty && !isExpanded {
            Button {
                withAnimation { isExpanded = true }
                fieldFocused = true
            } label: {
                Label("Add milestones to this goal", systemImage: "flag.badge.ellipsis")
            }
            .secondaryActionStyle(goal.tint, compact: true)
        } else {
            content
        }
    }

    private var content: some View {
        let done = goal.milestones.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Milestones", systemImage: "flag.checkered", trailing: AnyView(
                Text("\(done)/\(goal.milestones.count)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            ))
            if !goal.milestones.isEmpty {
                ProgressBar(progress: Double(done) / Double(goal.milestones.count), color: goal.color)
            }
            VStack(spacing: 0) {
                ForEach(goal.milestones) { milestone in
                    MilestoneRow(goal: goal, milestone: milestone)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(goal.tint)
                TextField("Add a milestone and press Return", text: $newTitle)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit(add)
            }
            .padding(.vertical, 6)
        }
        .glassCard(tint: goal.tint)
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.perform("Add Milestone") { $0.addMilestone(title, to: goal.id) }
        newTitle = ""
        fieldFocused = true
    }
}

private struct MilestoneRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let milestone: Milestone
    @State private var isEditing = false
    @State private var title = ""

    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    store.perform(milestone.isDone ? "Reopen Milestone" : "Complete Milestone") {
                        $0.toggleMilestone(milestone.id, in: goal.id)
                    }
                }
            } label: {
                Image(systemName: milestone.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(milestone.isDone ? AnyShapeStyle(goal.tint) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(milestone.isDone ? "Mark not done" : "Mark done")

            if isEditing {
                TextField("Milestone", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
                    .onEscape { isEditing = false }
            } else {
                Text(milestone.title)
                    .strikethrough(milestone.isDone, color: .secondary)
                    .foregroundStyle(milestone.isDone ? .secondary : .primary)
                    .onTapGesture(count: 2) { beginEditing() }
            }
            Spacer()
            if let completed = milestone.completedAt {
                Text(completed, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if let due = milestone.dueDate {
                Label(due.formatted(.dateTime.month(.abbreviated).day()), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(due < .now ? .orange : .secondary)
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Rename") { beginEditing() }
            Menu("Due Date") {
                Button("Today") { setDue(.now) }
                Button("Tomorrow") { setDue(Calendar.current.date(byAdding: .day, value: 1, to: .now)) }
                Button("In a Week") { setDue(Calendar.current.date(byAdding: .day, value: 7, to: .now)) }
                Button("In a Month") { setDue(Calendar.current.date(byAdding: .month, value: 1, to: .now)) }
                Divider()
                Button("None") { setDue(nil) }
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.perform("Delete Milestone") { $0.removeMilestone(milestone.id, from: goal.id) }
            }
        }
    }

    private func beginEditing() {
        title = milestone.title
        isEditing = true
    }

    private func commit() {
        var updated = milestone
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !updated.title.isEmpty {
            store.perform("Rename Milestone") { $0.updateMilestone(updated, in: goal.id) }
        }
        isEditing = false
    }

    private func setDue(_ date: Date?) {
        var updated = milestone
        updated.dueDate = date
        store.perform("Set Due Date") { $0.updateMilestone(updated, in: goal.id) }
    }
}
