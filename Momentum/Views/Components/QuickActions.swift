import MomentumCore
import SwiftUI

/// ⌘K: find a goal and act on it without the mouse.
/// Return runs the goal's one-tap action, ⌘Return opens it, arrows move the selection.
struct QuickActionsView: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        let goals = matches
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField("Start, log or open a goal…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit { run(goals, open: false) }
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        if goals.isEmpty {
                            Text(query.isEmpty ? "No goals yet." : "No goal matches \"\(query)\".")
                                .foregroundStyle(.secondary)
                                .padding(24)
                        }
                        ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                            QuickActionRow(goal: goal, isSelected: index == selection)
                                .id(goal.id)
                                .contentShape(Rectangle())
                                .onTapGesture { selection = index; run(goals, open: false) }
                                .onHover { if $0 { selection = index } }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selection) { _, index in
                    guard goals.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(goals[index].id) }
                }
            }
            Divider()
            HStack(spacing: 16) {
                hint("return", "Run action")
                hint("arrow.up.right.square", "⌘↩ Open")
                hint("arrow.up.arrow.down", "Move")
                Spacer()
                hint("escape", "Close")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 580, height: 440)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onKeyPress(.downArrow) {
            selection = min(goals.count - 1, selection + 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(0, selection - 1)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            run(goals, open: true)
            return .handled
        }
        .onExitCommand { dismiss() }
    }

    /// Active goals matching the query by name, category or book; today's unfinished ones first.
    private var matches: [Goal] {
        let engine = store.engine
        let now = store.now
        let text = query.trimmingCharacters(in: .whitespaces)
        let due = Set(engine.todayGoals(now: now).filter { !engine.isComplete($0, now: now) }.map(\.id))
        return engine.activeGoals
            .filter { goal in
                text.isEmpty || goal.name.localizedCaseInsensitiveContains(text) || goal.category.localizedCaseInsensitiveContains(text)
                    || goal.books.contains { $0.title.localizedCaseInsensitiveContains(text) }
            }
            .sorted { (due.contains($0.id) ? 0 : 1, engine.isRunning($0) ? 0 : 1) < (due.contains($1.id) ? 0 : 1, engine.isRunning($1) ? 0 : 1) }
    }

    private func run(_ goals: [Goal], open: Bool) {
        guard goals.indices.contains(selection) else { return }
        let goal = goals[selection]
        dismiss()
        let nothingToDo = (goal.kind == .books && goal.currentBook == nil)
            || (goal.kind == .milestones && !goal.milestones.contains { !$0.isDone })
        if open || nothingToDo {
            store.select(goal.id)
            return
        }
        switch goal.kind {
        case .time: store.toggleFocus(goal)
        default: store.quickAdd(goal)
        }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
    }
}

private struct QuickActionRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            GoalIcon(goal: goal, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name)
                    .font(.body.weight(.semibold))
                GoalProgressText(goal: goal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(actionTitle)
                .font(.callout.weight(.medium))
                .foregroundStyle(isSelected ? goal.tint : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? goal.tint.opacity(0.14) : .clear))
    }

    private var actionTitle: String {
        switch goal.kind {
        case .time: store.engine.isRunning(goal) ? "Stop focus" : "Start focus"
        case .count, .amount: goal.kind == .count && goal.quickAddStep == 1 ? "Log one" : "Add \(goal.format(goal.quickAddStep))"
        case .milestones: goal.milestones.first { !$0.isDone }.map { "Done: \($0.title)" } ?? "Open"
        case .books: goal.currentBook == nil ? "Open" : "Read \(Int(goal.quickAddStep)) pages"
        }
    }
}
