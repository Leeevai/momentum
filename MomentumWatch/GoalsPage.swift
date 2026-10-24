import MomentumCore
import SwiftUI

/// Every active goal, by period: today's and the ones not due today, each opening its page.
struct GoalsPage: View {
    @Environment(WatchStore.self) private var store
    @Binding var makesGoal: Bool

    var body: some View {
        let snapshot = store.snapshot
        let goals = snapshot.items + (snapshot.others ?? [])
        List {
            ForEach(Self.groups(of: goals), id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        NavigationLink(value: item.id) {
                            GoalRow(item: item)
                        }
                    }
                }
            }
            Section {
                Button {
                    makesGoal = true
                } label: {
                    Label("New Goal", systemImage: "plus")
                }
            } footer: {
                if snapshot.others == nil && snapshot.generatedAt != .distantPast {
                    Text("Update Momentum on your iPhone to see goals that aren't due today.")
                }
            }
        }
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NewGoalButton(makesGoal: $makesGoal)
            }
        }
    }

    /// Goals by period, daily first; from an iPhone that doesn't say, under Today.
    private static func groups(of items: [WatchSnapshot.Item]) -> [(title: String, items: [WatchSnapshot.Item])] {
        let unknown = items.filter { $0.period == nil }
        var groups: [(title: String, items: [WatchSnapshot.Item])] = unknown.isEmpty ? [] : [("Today", unknown)]
        for period in GoalPeriod.allCases {
            let matching = items.filter { $0.period == period }
            if !matching.isEmpty { groups.append((period.title, matching)) }
        }
        return groups
    }
}
