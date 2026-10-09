import MomentumCore
import SwiftUI

struct Sidebar: View {
    @Environment(GoalStore.self) private var store
    @State private var showsArchive = false

    var body: some View {
        @Bindable var store = store
        let engine = store.engine
        let summary = engine.todaySummary(now: store.now)
        List(selection: $store.route) {
            Section {
                Label("Today", systemImage: "sun.max.fill")
                    .badge(summary.total - summary.done)
                    .tag(Route.today)
                Label("Insights", systemImage: "chart.bar.xaxis")
                    .tag(Route.insights)
            }

            ForEach(groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.goals) { goal in
                        SidebarGoalRow(goal: goal)
                            .tag(Route.goal(goal.id))
                            .contextMenu { GoalContextMenu(goal: goal) }
                    }
                    .onMove { source, destination in
                        move(in: group.goals, from: source, to: destination)
                    }
                }
            }

            if !engine.archivedGoals.isEmpty {
                Section(isExpanded: $showsArchive) {
                    ForEach(filter(engine.archivedGoals)) { goal in
                        SidebarGoalRow(goal: goal)
                            .tag(Route.goal(goal.id))
                            .opacity(0.6)
                            .contextMenu { GoalContextMenu(goal: goal) }
                    }
                } header: {
                    Text("Archived")
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search goals")
        .safeAreaInset(edge: .bottom) {
            if let session = store.data.session, let goal = store.goal(session.goalID) {
                MiniFocusPlayer(goal: goal, session: session)
                    .padding(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.data.session?.goalID)
    }

    private struct Group {
        var name: String
        var goals: [Goal]
    }

    /// Active goals grouped by category, in the order their first goal appears.
    private var groups: [Group] {
        var order: [String] = []
        var byName: [String: [Goal]] = [:]
        for goal in filter(store.engine.activeGoals) {
            let name = goal.category.isEmpty ? "Goals" : goal.category
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(goal)
        }
        return order.map { Group(name: $0, goals: byName[$0] ?? []) }
    }

    private func filter(_ goals: [Goal]) -> [Goal] {
        let query = store.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return goals }
        return goals.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query)
                || $0.books.contains { $0.title.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Reorders within one category section by rewriting those goals' slots in the full list.
    private func move(in section: [Goal], from source: IndexSet, to destination: Int) {
        var reordered = section
        reordered.move(fromOffsets: source, toOffset: destination)
        let sectionIDs = Set(section.map(\.id))
        let all = store.data.goals
        let slots = all.indices.filter { sectionIDs.contains(all[$0].id) }
        store.perform("Reorder Goals") { data in
            for (slot, goal) in zip(slots, reordered) {
                if let current = data.goal(goal.id) { data.goals[slot] = current }
            }
        }
    }
}

private struct SidebarGoalRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        let engine = store.engine
        let streak = engine.streak(for: goal, now: store.now)
        HStack(spacing: 8) {
            GoalIcon(goal: goal, size: 24)
            Text(goal.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            if engine.isRunning(goal) {
                Image(systemName: "waveform")
                    .foregroundStyle(goal.tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else if goal.isOnBreak(at: store.now) {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                    .help("On a break")
            }
            if streak.current > 0 {
                StreakBadge(count: streak.current, unit: streak.unit)
            }
            GoalRing(goal: goal, lineWidth: 3, showsIcon: false)
                .frame(width: 16, height: 16)
        }
    }
}

/// The running session, pinned to the bottom of the sidebar.
private struct MiniFocusPlayer: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let session: FocusSession

    var body: some View {
        HStack(spacing: 10) {
            Text(goal.icon)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(goal.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                SessionClockText(session: session)
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(goal.tint)
            }
            Spacer(minLength: 0)
            Button {
                store.togglePause()
            } label: {
                Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(CircleButtonStyle(tint: goal.tint, size: 26, prominent: false))
            .help(session.isRunning ? "Pause" : "Resume")
            Button {
                store.stopFocus()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(CircleButtonStyle(tint: goal.tint, size: 26))
            .help("Stop and save")
        }
        .glassCard(tint: goal.tint, cornerRadius: 14, padding: 10, highlighted: true)
        .contentShape(Rectangle())
        .onTapGesture { store.select(goal.id) }
    }
}

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
