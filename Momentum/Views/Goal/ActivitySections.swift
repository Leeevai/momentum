import Charts
import MomentumCore
import SwiftUI

/// Daily amounts for the last 30 days, with the daily target drawn as a rule.
struct ActivityChartCard: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    @State private var range = 30
    @State private var selectedDay: Date?

    var body: some View {
        let engine = store.engine
        let points = engine.dailyAmounts(for: goal, days: range, now: store.now)
        let isTime = goal.kind == .time
        let scale: Double = isTime ? 60 : 1
        let selected = selectedDay.flatMap { day in points.first { engine.calendar.isDate($0.day, inSameDayAs: day) } }
        let dailyTarget = goal.effectivePeriod == .daily && goal.kind != .milestones && goal.kind != .books ? goal.target / scale : nil

        let peak = max(points.map(\.amount).max() ?? 0, dailyTarget.map { $0 * scale } ?? 0) / scale

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(goal.kind == .books ? "Pages read" : (isTime ? "Time per day" : "Per day"), systemImage: "chart.bar.fill")
                    .font(.headline)
                if let dailyTarget {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(goal.tint.opacity(0.7))
                            .frame(width: 14, height: 1.5)
                        Text("target \(isTime ? Formatting.duration(dailyTarget * 60) : Formatting.number(dailyTarget))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                }
                Spacer()
                if let selected {
                    Text("\(selected.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): \(goal.kind == .books ? "\(Formatting.number(selected.amount)) pages" : goal.format(selected.amount))")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(goal.tint)
                        .monospacedDigit()
                }
                Picker("Range", selection: $range) {
                    Text("2W").tag(14)
                    Text("1M").tag(30)
                    Text("3M").tag(90)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Amount", point.amount / scale)
                    )
                    .foregroundStyle(goal.color.linear)
                    .cornerRadius(range > 60 ? 1.5 : 4)
                    .opacity(selected == nil || selected?.day == point.day ? 1 : 0.45)
                }
                if let dailyTarget {
                    RuleMark(y: .value("Target", dailyTarget))
                        .foregroundStyle(goal.tint.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
            }
            .chartXSelection(value: $selectedDay)
            .chartYAxis {
                AxisMarks(position: .leading, values: isTime ? .stride(by: Self.minuteStride(for: peak)) : .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(isTime ? Formatting.duration(number * 60) : Formatting.number(number))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range > 60 ? 14 : (range > 20 ? 7 : 2))) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 190)
            .animation(.easeInOut(duration: 0.35), value: range)
        }
        .glassCard(tint: goal.tint)
    }

    /// Round gridlines for a minutes axis: 15m, 30m, 1h or 2h apart.
    static func minuteStride(for peakMinutes: Double) -> Double {
        switch peakMinutes {
        case ..<60: 15
        case ..<150: 30
        case ..<360: 60
        default: 120
        }
    }
}

struct HeatmapCard: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    /// Books log pages per book and milestones are checked off, so only these log by day.
    private var logsByDay: Bool { goal.kind == .time || goal.kind == .count || goal.kind == .amount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Activity", systemImage: "square.grid.3x3.fill")
                    .font(.headline)
                Spacer()
                HStack(spacing: 3) {
                    Text("Less")
                    ForEach([0.0, 0.33, 0.66, 1.0], id: \.self) { level in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(level == 0 ? Color.primary.opacity(0.09) : goal.tint.opacity(0.25 + 0.75 * level))
                            .frame(width: 11, height: 11)
                    }
                    Text("More")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Heatmap(engine: store.engine, goal: goal, now: store.now, maxCell: 15, onSelect: logsByDay ? { day in
                store.sheet = .log(goalID: goal.id, day: day)
            } : nil)
                .frame(height: 7 * 15 + 6 * 3)
            if logsByDay {
                Text("Click a day to log progress for it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .glassCard(tint: goal.tint)
    }
}

/// Recent log entries with notes; right-click to delete.
struct HistorySection: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    @State private var showsAll = false

    var body: some View {
        let entries = store.engine.entries(for: goal)
        let visible = showsAll ? entries : Array(entries.prefix(8))
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("History", systemImage: "clock.arrow.circlepath", trailing: AnyView(
                Text("\(entries.count) entries")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            ))
            if entries.isEmpty {
                Text("Nothing logged yet. Your sessions and check-ins will show up here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(visible) { entry in
                    HistoryRow(goal: goal, entry: entry)
                    if entry.id != visible.last?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
            if entries.count > 8 {
                Button(showsAll ? "Show less" : "Show all \(entries.count)") {
                    withAnimation { showsAll.toggle() }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(goal.tint)
            }
        }
        .glassCard(tint: goal.tint)
    }
}

private struct HistoryRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.source == .timer ? "timer" : (entry.amount < 0 ? "arrow.uturn.backward" : "square.and.pencil"))
                .foregroundStyle(entry.amount < 0 ? Color.secondary : goal.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(amountText)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(entry.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.sheet = .log(goalID: goal.id, entry: entry) }
        .contextMenu {
            Button("Edit…") { store.sheet = .log(goalID: goal.id, entry: entry) }
            Divider()
            Button("Delete Entry", role: .destructive) { store.deleteEntry(entry) }
        }
        .help("Double-click to edit")
    }

    private var amountText: String {
        let sign = entry.amount < 0 ? "−" : "+"
        let magnitude = abs(entry.amount)
        let value = goal.kind == .books ? "\(Formatting.number(magnitude)) \(Formatting.unit("pages", for: magnitude))" : goal.format(magnitude)
        return "\(sign)\(value)"
    }

    private var detail: String {
        let book = entry.bookID.flatMap { id in goal.books.first { $0.id == id }?.title }
        return [book, entry.note.isEmpty ? nil : entry.note].compactMap { $0 }.joined(separator: " · ")
    }
}
