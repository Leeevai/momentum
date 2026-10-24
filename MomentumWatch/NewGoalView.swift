import MomentumCore
import SwiftUI
import WatchKit

/// New Goal: a goal of your own (a name, time or times, a target, daily or weekly) or one of
/// Momentum's templates. Adding sends it to the iPhone, which makes it, and closes.
struct NewGoalView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        CustomGoalForm(add: add)
                    } label: {
                        Label("Your Own Goal", systemImage: "square.and.pencil")
                    }
                }
                Section("Start From") {
                    ForEach(GoalTemplate.all) { template in
                        NavigationLink {
                            TemplatePage(template: template, add: add)
                        } label: {
                            TemplateRow(template: template)
                        }
                    }
                }
            }
            .navigationTitle("New Goal")
        }
    }

    private func add(_ goal: WatchNewGoal) {
        store.perform(.addGoal(goal: goal))
        WKInterfaceDevice.current().play(.success)
        dismiss()
    }
}

private struct TemplateRow: View {
    let template: GoalTemplate
    @Environment(\.watchPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: template.prototype.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.color(template.prototype.color))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(template.prototype.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(template.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A template, to add with one more tap: a stray tap in the list adds nothing.
private struct TemplatePage: View {
    let template: GoalTemplate
    let add: (WatchNewGoal) -> Void
    @Environment(\.watchPalette) private var palette

    var body: some View {
        let tint = palette.color(template.prototype.color)
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: template.prototype.symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(template.prototype.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(template.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    add(WatchNewGoal(template: template))
                } label: {
                    Label("Add Goal", systemImage: "plus")
                }
                .tint(tint)
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(palette.backdrop(template.prototype.color), for: .navigation)
    }
}

/// A goal of your own: what it's called, whether it counts times or time, and how much a day
/// or a week.
private struct CustomGoalForm: View {
    let add: (WatchNewGoal) -> Void
    @State private var name = ""
    @State private var kind: GoalKind = .count
    @State private var period: GoalPeriod = .daily
    @State private var times = 3
    @State private var minutes = 30

    var body: some View {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        List {
            Section {
                TextField("Name", text: $name)
            }
            Section {
                Picker("Track", selection: $kind) {
                    Text("Times").tag(GoalKind.count)
                    Text("Time").tag(GoalKind.time)
                }
                Picker("Every", selection: $period) {
                    Text("Day").tag(GoalPeriod.daily)
                    Text("Week").tag(GoalPeriod.weekly)
                }
            }
            Section("Target") {
                if kind == .time {
                    Stepper(value: $minutes, in: 5...600, step: 5) {
                        Text(Formatting.duration(Double(minutes * 60)))
                            .monospacedDigit()
                    }
                } else {
                    Stepper(value: $times, in: 1...100) {
                        Text(times == 1 ? "1 time" : "\(times) times")
                            .monospacedDigit()
                    }
                }
            }
            Section {
                Button {
                    let target = kind == .time ? Double(minutes * 60) : Double(times)
                    add(WatchNewGoal(name: trimmed, kind: kind, period: period, target: target))
                } label: {
                    Label("Add Goal", systemImage: "plus")
                }
                .disabled(trimmed.isEmpty)
            }
        }
        .navigationTitle("Your Goal")
    }
}
