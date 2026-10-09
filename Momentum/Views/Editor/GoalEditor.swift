import AppKit
import MomentumCore
import SwiftUI

struct GoalEditor: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let isNew: Bool
    var onBack: (() -> Void)?
    @State private var draft: Goal
    @State private var hasReminder: Bool
    @State private var reminderTime: Date
    @State private var hasDeadline: Bool

    init(goal: Goal, isNew: Bool, onBack: (() -> Void)? = nil) {
        self.isNew = isNew
        self.onBack = onBack
        _draft = State(initialValue: goal)
        _hasReminder = State(initialValue: goal.reminder?.isEnabled ?? false)
        let reminder = goal.reminder ?? ReminderSchedule()
        _reminderTime = State(initialValue: Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: .now) ?? .now)
        _hasDeadline = State(initialValue: goal.deadline != nil)
    }

    /// The tracking kind is fixed once a goal has history, since amounts are stored in its units.
    private var kindIsLocked: Bool {
        !isNew && store.data.entries.contains { $0.goalID == draft.id }
    }

    private var isValid: Bool {
        let named = !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let targeted = draft.kind == .milestones || draft.target > 0
        let scheduled = draft.effectivePeriod != .daily || !draft.weekdays.isEmpty
        return named && targeted && scheduled && !draft.icon.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
            Form {
                basics
                tracking
                schedule
                extras
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            footer
        }
        .frame(width: 580, height: 720)
        .background(AmbientBackground(primary: draft.tint, secondary: draft.color.highlight))
        .onChange(of: draft.kind) { old, kind in
            guard isNew, old != kind else { return }
            applyDefaults(for: kind)
        }
    }

    // MARK: - Sections

    private var preview: some View {
        HStack(spacing: 14) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(CircleButtonStyle(tint: .secondary, size: 28, prominent: false))
                .help("Back to templates")
            }
            GoalIcon(goal: draft, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.name.isEmpty ? "New goal" : draft.name)
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                Text("\(draft.targetDescription) · \(draft.scheduleDescription())")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
            Spacer()
        }
        .padding(20)
        .animation(.snappy, value: draft)
    }

    private var basics: some View {
        Section {
            TextField("Name", text: $draft.name, prompt: Text("e.g. Deep work, Read, Gym"))
            HStack {
                TextField("Icon", text: $draft.icon)
                    .frame(maxWidth: 140)
                    .onChange(of: draft.icon) { _, value in
                        if value.count > 1 { draft.icon = String(value.suffix(1)) }
                    }
                Button("Emoji & Symbols…") { NSApp.orderFrontCharacterPalette(nil) }
                    .controlSize(.small)
            }
            LabeledContent("Color") {
                ColorChooser(selection: $draft.color)
            }
            LabeledContent("Category") {
                HStack {
                    TextField("Category", text: $draft.category, prompt: Text("None"))
                        .labelsHidden()
                    Menu {
                        ForEach(categorySuggestions, id: \.self) { name in
                            Button(name) { draft.category = name }
                        }
                        if !draft.category.isEmpty {
                            Divider()
                            Button("None") { draft.category = "" }
                        }
                    } label: {
                        Image(systemName: "tag")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            TextField("Why it matters", text: $draft.details, prompt: Text("Optional: a note to your future self"), axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var tracking: some View {
        Section {
            Picker("Track", selection: $draft.kind) {
                ForEach(GoalKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.symbolName).tag(kind)
                }
            }
            .disabled(kindIsLocked)
            Text(kindIsLocked ? "The tracking type can't change once a goal has history." : draft.kind.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if draft.kind == .count || draft.kind == .amount {
                TextField("Unit", text: $draft.unit, prompt: Text(draft.kind == .count ? "workouts, glasses…" : "pages, km, words, $…"))
            }
            if draft.kind.usesPeriod {
                Picker("Period", selection: $draft.period) {
                    ForEach(GoalPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                TargetField(goal: $draft)
            }
        } header: {
            Text("Tracking")
        }
    }

    @ViewBuilder
    private var schedule: some View {
        if draft.kind.usesPeriod && draft.period == .daily {
            Section("Days") {
                WeekdayChooser(selection: $draft.weekdays, tint: draft.tint)
                Text("Days off never break your streak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if draft.kind.usesPeriod && draft.period == .total {
            Section("Deadline") {
                Toggle("Finish by a date", isOn: $hasDeadline.animation())
                if hasDeadline {
                    DatePicker("Deadline", selection: Binding(
                        get: { draft.deadline ?? Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now },
                        set: { draft.deadline = $0 }
                    ), in: Date.now..., displayedComponents: .date)
                }
            }
        }
    }

    private var extras: some View {
        Section("Extras") {
            if draft.kind == .time {
                Picker("Focus sessions", selection: $draft.focusMinutes) {
                    Text("Open-ended").tag(Int?.none)
                    ForEach(FocusLengthMenu.lengths, id: \.self) { Text("\($0) minutes").tag(Int?.some($0)) }
                }
            }
            if draft.kind != .milestones {
                QuickStepField(goal: $draft)
            }
            Toggle("Daily reminder", isOn: $hasReminder.animation())
            if hasReminder {
                DatePicker("Remind me at", selection: $reminderTime, displayedComponents: .hourAndMinute)
                Text("Skipped automatically on days the goal is already done.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            if !isNew {
                Text("Links, milestones and books are edited on the goal's page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Add Goal" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PillButtonStyle(tint: draft.tint))
                .disabled(!isValid)
        }
        .padding(16)
        .background(.bar)
    }

    // MARK: - Behavior

    private var categorySuggestions: [String] {
        var names = GoalCategory.presets
        for goal in store.data.goals where !goal.category.isEmpty && !names.contains(goal.category) {
            names.append(goal.category)
        }
        return names
    }

    private func applyDefaults(for kind: GoalKind) {
        draft.quickAddStep = kind.defaultStep
        switch kind {
        case .time: draft.target = 30 * 60; draft.unit = ""
        case .count: draft.target = 1; if draft.unit.isEmpty { draft.unit = "times" }
        case .amount: draft.target = 10
        case .books: draft.target = 12; draft.period = .yearly; draft.unit = ""
        case .milestones: draft.target = 0
        }
    }

    private func save() {
        var goal = draft
        goal.name = goal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        goal.unit = goal.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hasDeadline || goal.period != .total { goal.deadline = nil }
        if hasReminder {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            goal.reminder = ReminderSchedule(isEnabled: true, hour: parts.hour ?? 18, minute: parts.minute ?? 0)
        } else {
            goal.reminder = nil
        }
        store.perform(isNew ? "Add Goal" : "Edit Goal") { $0.upsert(goal) }
        if isNew { store.select(goal.id) }
        dismiss()
    }
}

/// The per-period target, in hours and minutes for time goals.
private struct TargetField: View {
    @Binding var goal: Goal

    var body: some View {
        if goal.kind == .time {
            LabeledContent("Target") {
                HStack(spacing: 6) {
                    Stepper(value: hours, in: 0...999) {
                        Text("\(hours.wrappedValue) h").monospacedDigit()
                    }
                    Stepper(value: minutes, in: 0...55, step: 5) {
                        Text("\(minutes.wrappedValue) m").monospacedDigit()
                    }
                    Text("a \(goal.period == .total ? "total" : goal.period.noun)")
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            LabeledContent("Target") {
                HStack(spacing: 6) {
                    TextField("Target", value: $goal.target, format: .number.precision(.fractionLength(0...2)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Stepper("", value: $goal.target, in: 0...1_000_000, step: 1)
                        .labelsHidden()
                    Text("\(goal.displayUnit) \(goal.period == .total ? "in total" : "a \(goal.period.noun)")")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hours: Binding<Int> {
        Binding(
            get: { Int(goal.target) / 3600 },
            set: { goal.target = Double($0 * 3600 + (Int(goal.target) % 3600)) }
        )
    }

    private var minutes: Binding<Int> {
        Binding(
            get: { (Int(goal.target) % 3600) / 60 },
            set: { goal.target = Double((Int(goal.target) / 3600) * 3600 + $0 * 60) }
        )
    }
}

/// The quick-add increment: minutes for time goals, pages per tap for books.
private struct QuickStepField: View {
    @Binding var goal: Goal

    var body: some View {
        switch goal.kind {
        case .time:
            Stepper(value: Binding(get: { Int(goal.quickAddStep / 60) }, set: { goal.quickAddStep = Double($0 * 60) }), in: 1...240, step: 5) {
                LabeledContent("Quick add", value: Formatting.duration(goal.quickAddStep))
            }
        case .books:
            Stepper(value: Binding(get: { Int(goal.quickAddStep) }, set: { goal.quickAddStep = Double($0) }), in: 1...200, step: 5) {
                LabeledContent("Pages per tap", value: "\(Int(goal.quickAddStep))")
            }
        case .count, .amount:
            LabeledContent("Quick add") {
                HStack {
                    TextField("Step", value: $goal.quickAddStep, format: .number.precision(.fractionLength(0...2)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text(goal.displayUnit).foregroundStyle(.secondary)
                }
            }
        case .milestones:
            EmptyView()
        }
    }
}

struct ColorChooser: View {
    @Binding var selection: GoalColor

    var body: some View {
        HStack(spacing: 6) {
            ForEach(GoalColor.allCases) { option in
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    Circle()
                        .fill(option.linear)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(selection == option ? 0.9 : 0), lineWidth: 2).padding(-3))
                        .scaleEffect(selection == option ? 1.1 : 1)
                }
                .buttonStyle(.plain)
                .help(option.rawValue.capitalized)
                .accessibilityLabel(option.rawValue.capitalized)
            }
        }
        .padding(.vertical, 3)
    }
}

struct WeekdayChooser: View {
    @Binding var selection: Set<Int>
    var tint: Color = .accentColor

    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(order, id: \.self) { day in
                    let isOn = selection.contains(day)
                    Button {
                        withAnimation(.snappy) {
                            if isOn { selection.remove(day) } else { selection.insert(day) }
                        }
                    } label: {
                        Text(symbols[day - 1])
                            .font(.caption.weight(.semibold))
                            .frame(width: 44, height: 28)
                            .background(Capsule().fill(isOn ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button("Every day") { selection = Set(1...7) }
                Button("Weekdays") { selection = Set(2...6) }
                Button("Weekends") { selection = [1, 7] }
            }
            .controlSize(.small)
        }
    }
}
