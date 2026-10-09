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
                Label("Journal", systemImage: "book.closed.fill")
                    .tag(Route.journal)
                Label("Insights", systemImage: "chart.bar.xaxis")
                    .tag(Route.insights)
                Label("Awards", systemImage: "trophy.fill")
                    .badge(earnedCount)
                    .tag(Route.awards)
            }

            ForEach(groups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.goals) { goal in
                        SidebarGoalRow(goal: goal)
                            .tag(Route.goal(goal.id))
                            .contextMenu { GoalContextMenu(goal: goal) }
                    }
                    .onMove { source, destination in
                        store.reorder(group.goals, from: source, to: destination)
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

    private var earnedCount: Int {
        store.data.achievements.keys.filter { Achievement.with(id: $0) != nil }.count
    }

    private struct GoalGroup {
        var name: String
        var goals: [Goal]
    }

    /// Active goals grouped by category, in the order their first goal appears.
    private var groups: [GoalGroup] {
        var order: [String] = []
        var byName: [String: [Goal]] = [:]
        for goal in filter(store.engine.activeGoals) {
            let name = goal.category.isEmpty ? "Goals" : goal.category
            if byName[name] == nil { order.append(name) }
            byName[name, default: []].append(goal)
        }
        return order.map { GoalGroup(name: $0, goals: byName[$0] ?? []) }
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
            GoalIcon(goal: goal, size: 28)
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
