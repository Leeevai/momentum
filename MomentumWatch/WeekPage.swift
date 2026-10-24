import Charts
import MomentumCore
import SwiftUI

/// The last seven days: time focused each day, daily goals met, active days, the longest
/// streak and the goals focused on most.
struct WeekPage: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        Group {
            if let week = store.snapshot.week {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        FocusSummary(week: week)
                        GoalsMetRow(week: week)
                        WeekFacts(week: week)
                        if !week.topGoals.isEmpty {
                            TopGoals(goals: week.topGoals)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            } else {
                ContentUnavailableView("No week yet", systemImage: "chart.bar.fill",
                                       description: Text("Update Momentum on your iPhone and open it to see your week here."))
            }
        }
        .navigationTitle("Week")
    }
}

/// Time focused this week, how it compares with the week before, and a bar for each day.
private struct FocusSummary: View {
    let week: WatchWeek
    @Environment(\.watchPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Focus")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Formatting.duration(week.focus))
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
            if let change {
                Label(change.text, systemImage: change.isUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2)
                    .foregroundStyle(change.isUp ? palette.success : .secondary)
            }
            FocusChart(days: week.days)
                .frame(height: 64)
        }
    }

    /// The change from the seven days before, when there was focus then to compare with.
    private var change: (text: String, isUp: Bool)? {
        guard week.previousFocus > 0 else { return nil }
        let ratio = week.focus / week.previousFocus - 1
        let percent = Int((abs(ratio) * 100).rounded())
        return ("\(percent)% on last week", ratio >= 0)
    }
}

private struct FocusChart: View {
    let days: [WatchWeek.Day]
    @Environment(\.watchPalette) private var palette

    var body: some View {
        Chart(days, id: \.date) { day in
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.focus / 60))
                .foregroundStyle(palette.accentColor.gradient)
                .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis(.hidden)
    }
}

/// Daily goals met of those due, with a small ring for each day.
private struct GoalsMetRow: View {
    let week: WatchWeek
    @Environment(\.watchPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(week.due > 0 ? "\(week.met) of \(week.due) daily goals met" : "No daily goals this week")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(week.days, id: \.date) { day in
                    DayDot(day: day)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct DayDot: View {
    let day: WatchWeek.Day
    @Environment(\.watchPalette) private var palette

    var body: some View {
        let fraction = day.due > 0 ? Double(day.met) / Double(day.due) : 0
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(palette.success.opacity(0.22), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.001, min(fraction, 1)))
                    .stroke(palette.success, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            Text(day.date, format: .dateTime.weekday(.narrow))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide)))
        .accessibilityValue("\(day.met) of \(day.due) met")
    }
}

/// Active days and the longest streak running.
private struct WeekFacts: View {
    let week: WatchWeek
    @Environment(\.watchPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Fact(value: "\(week.activeDays)/7", label: "Active days", symbol: "calendar", tint: palette.accentColor)
            Fact(value: "\(week.longestStreak)", label: "Best streak", symbol: "flame.fill", tint: palette.streak)
        }
    }
}

private struct Fact: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The goals focused on most this week.
private struct TopGoals: View {
    let goals: [WatchWeek.Focus]
    @Environment(\.watchPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Most focus")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(goals) { goal in
                HStack(spacing: 8) {
                    Image(systemName: goal.symbol)
                        .foregroundStyle(palette.color(goal.color))
                        .frame(width: 20)
                    Text(goal.name)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Formatting.duration(goal.seconds))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.footnote)
            }
        }
    }
}
