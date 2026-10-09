import MomentumCore
import SwiftUI

// MARK: - Plan

/// The morning plan: an intention and up to three priorities.
struct PlanSheet: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: DayID
    @State private var intention = ""
    @State private var priorities: [UUID] = []
    @Namespace private var badges

    var body: some View {
        let engine = store.engine
        let date = day.date()
        let today = engine.todayGoals(now: date)
        let others = engine.activeGoals.filter { goal in !today.contains { $0.id == goal.id } }
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(symbol: "sun.horizon.fill", tint: .orange, title: "Plan your day",
                        subtitle: date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            VStack(alignment: .leading, spacing: 8) {
                Text("Intention")
                    .font(.headline)
                TextField("What would make today a good day?", text: $intention, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.title3, design: .serif))
                    .lineLimit(1...3)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.05)))
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Priorities")
                        .font(.headline)
                    Text("Pick up to three.")
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(today + others) { goal in
                            PriorityTile(goal: goal, rank: priorities.firstIndex(of: goal.id).map { $0 + 1 },
                                         isDue: today.contains { $0.id == goal.id }, badges: badges) {
                                toggle(goal.id)
                            }
                            .disabled(!priorities.contains(goal.id) && priorities.count >= JournalEntry.maxPriorities)
                        }
                    }
                    .padding(2)
                }
                .frame(maxHeight: 300)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Plan") { save() }
                    .primaryActionStyle(.orange)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .sheetFrame(width: 560)
        .onAppear {
            let entry = store.data.journalEntry(for: day)
            intention = entry?.intention ?? ""
            priorities = entry?.priorities ?? []
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            if let index = priorities.firstIndex(of: id) {
                priorities.remove(at: index)
            } else if priorities.count < JournalEntry.maxPriorities {
                priorities.append(id)
            }
        }
    }

    private func save() {
        let trimmed = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateJournal(day, "Plan Day") { entry in
            entry.intention = trimmed
            entry.priorities = priorities
        }
        dismiss()
    }
}

private struct PriorityTile: View {
    let goal: Goal
    let rank: Int?
    let isDue: Bool
    let badges: Namespace.ID
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GoalIcon(goal: goal, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(isDue ? "Due today" : goal.targetDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let rank {
                    Text("\(rank)")
                        .font(.system(.callout, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(goal.color.gradient))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(rank != nil ? goal.tint.opacity(0.16) : Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(rank != nil ? goal.tint.opacity(0.7) : .clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reflect

/// The evening reflection: mood, energy, a win and a few lines about the day.
struct ReflectSheet: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: DayID
    @State private var mood: Mood?
    @State private var energy: Energy?
    @State private var win = ""
    @State private var reflection = ""

    var body: some View {
        let date = day.date()
        let summary = store.engine.daySummary(date, now: store.now)
        VStack(alignment: .leading, spacing: 20) {
            SheetHeader(symbol: "moon.stars.fill", tint: .indigo, title: "How did it go?",
                        subtitle: date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            HStack(spacing: 10) {
                if !summary.due.isEmpty {
                    Label("\(summary.met.count) of \(summary.due.count) goals done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if summary.focusSeconds > 0 {
                    Label("\(Formatting.duration(summary.focusSeconds)) focused", systemImage: "timer")
                        .foregroundStyle(.indigo)
                }
            }
            .font(.callout.weight(.medium))
            VStack(alignment: .leading, spacing: 8) {
                Text("Mood").font(.headline)
                MoodPicker(selection: $mood)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Energy").font(.headline)
                EnergyPicker(selection: $energy)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("A win").font(.headline)
                TextField("Something that went well", text: $win)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes").font(.headline)
                TextEditor(text: $reflection)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 110)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(0.05)))
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .primaryActionStyle(.indigo)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .sheetFrame(width: 520)
        .onAppear {
            let entry = store.data.journalEntry(for: day)
            mood = entry?.mood
            energy = entry?.energy
            win = entry?.win ?? ""
            reflection = entry?.reflection ?? ""
        }
    }

    private func save() {
        store.updateJournal(day, "Reflect") { entry in
            entry.mood = mood
            entry.energy = energy
            entry.win = win.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.reflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        dismiss()
    }
}

// MARK: - Pickers

/// Five weather symbols, from storm to sun. The selection glides between them.
struct MoodPicker: View {
    @Binding var selection: Mood?
    var compact = false
    @Namespace private var marker

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            ForEach(Mood.allCases) { mood in
                ScaleOption(symbol: mood.symbolName, title: mood.title, tint: mood.tint, isSelected: selection == mood,
                            compact: compact, marker: marker) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selection = selection == mood ? nil : mood }
                }
            }
        }
    }
}

/// Five batteries, from drained to charged.
struct EnergyPicker: View {
    @Binding var selection: Energy?
    var compact = false
    @Namespace private var marker

    var body: some View {
        HStack(spacing: compact ? 4 : 8) {
            ForEach(Energy.allCases) { energy in
                ScaleOption(symbol: energy.symbolName, title: energy.title, tint: energy.tint, isSelected: selection == energy,
                            compact: compact, marker: marker) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selection = selection == energy ? nil : energy }
                }
            }
        }
    }
}

private struct ScaleOption: View {
    let symbol: String
    let title: String
    let tint: Color
    let isSelected: Bool
    let compact: Bool
    let marker: Namespace.ID
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: compact ? 18 : 24))
                    .foregroundStyle(tint)
                    .scaleEffect(isSelected ? 1.15 : 1)
                    .symbolEffect(.bounce, value: isSelected)
                if !compact {
                    Text(title)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 6 : 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.18))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.6), lineWidth: 1.5))
                        .matchedGeometryEffect(id: "marker", in: marker)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// An icon tile, title and subtitle at the top of a sheet.
struct SheetHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint.gradient))
                .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
