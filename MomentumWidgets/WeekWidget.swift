import MomentumCore
import SwiftUI
import WidgetKit

/// The last seven days of focus: a bar a day, stacked in the colors of the goals behind it.
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Week", provider: TodayProvider()) { entry in
            WeekWidgetView(entry: entry)
                .widgetBackground(.indigo)
                .widgetURL(DeepLink.insights.url)
        }
        .configurationDisplayName("Week of Focus")
        .description("Focus over the last seven days, by goal, against the week before.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomentumEntry

    var body: some View {
        let report = entry.engine.insights(days: 7, now: entry.date)
        let days = Self.days(report, engine: entry.engine, now: entry.date)
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 6) {
                summary(report, compact: true)
                Spacer(minLength: 0)
                WeekBars(days: days, showsLabels: false)
                    .frame(height: 50)
            }
        } else {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    summary(report, compact: false)
                    Spacer(minLength: 0)
                    Label("\(report.activeDays) of 7 days active", systemImage: "flame.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .frame(width: 118, alignment: .leading)
                WeekBars(days: days, showsLabels: true)
            }
        }
    }

    private func summary(_ report: InsightsReport, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("This week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Formatting.duration(report.totalFocusSeconds))
                .font(.system(compact ? .title2 : .title, design: .rounded, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let change = report.focusChange {
                Label((change >= 0 ? "Up " : "Down ") + Formatting.percent(abs(change)),
                      systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(change >= 0 ? .green : .orange)
            }
        }
    }

    /// Seven days, oldest first, each with its focus split by goal (largest first).
    static func days(_ report: InsightsReport, engine: ProgressEngine, now: Date) -> [WeekBars.Day] {
        let byDay = Dictionary(grouping: report.focusByDay, by: { engine.dayKey($0.day) })
        return (0..<7).map { offset in
            let day = engine.day(offset - 6, from: now)
            let parts = (byDay[engine.dayKey(day)] ?? [])
                .sorted { $0.seconds > $1.seconds }
                .map { WeekBars.Part(color: engine.goal($0.goalID)?.tint ?? .gray, seconds: $0.seconds) }
            return WeekBars.Day(date: day, parts: parts, isToday: offset == 6)
        }
    }
}

/// Seven bars, scaled to the busiest day.
struct WeekBars: View {
    struct Part {
        let color: Color
        let seconds: Double
    }

    struct Day {
        let date: Date
        let parts: [Part]
        let isToday: Bool
        var total: Double { parts.reduce(0) { $0 + $1.seconds } }
    }

    let days: [Day]
    var showsLabels = true

    var body: some View {
        let peak = max(days.map(\.total).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        VStack(spacing: 1.5) {
                            Spacer(minLength: 0)
                            if day.total == 0 {
                                Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 4)
                            }
                            ForEach(Array(day.parts.reversed().enumerated()), id: \.offset) { _, part in
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(part.color.gradient)
                                    .frame(height: max(3, proxy.size.height * part.seconds / peak - 1.5))
                            }
                        }
                    }
                    if showsLabels {
                        Text(day.date, format: .dateTime.weekday(.narrow))
                            .font(.caption2.weight(day.isToday ? .bold : .medium))
                            .foregroundStyle(day.isToday ? .primary : .secondary)
                    }
                }
            }
        }
    }
}
