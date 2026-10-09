import Charts
import MomentumCore
import SwiftUI

struct InsightsView: View {
    @Environment(GoalStore.self) private var store
    @State private var days = 30

    var body: some View {
        let engine = store.engine
        let report = engine.insights(days: days, now: store.now)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Insights")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("How the last \(days) days went.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Range", selection: $days.animation(.easeInOut)) {
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("Year").tag(365)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    StatTile(title: "Focused", value: Formatting.duration(report.totalFocusSeconds), systemImage: "timer", tint: .indigo,
                             caption: "\(Formatting.duration(report.averageFocusPerDay)) a day on average")
                    StatTile(title: "Active days", value: "\(report.activeDays) of \(days)", systemImage: "calendar.badge.checkmark", tint: .green,
                             caption: Formatting.percent(Double(report.activeDays) / Double(days)) + " of days")
                    StatTile(title: "Best streak now", value: "\(engine.longestCurrentStreak(now: store.now))", systemImage: "flame.fill", tint: .orange)
                    StatTile(title: "Books finished", value: "\(report.booksFinished)", systemImage: "books.vertical.fill", tint: .brown,
                             caption: "\(Formatting.number(report.pagesRead)) pages read")
                    StatTile(title: "Milestones", value: "\(report.milestonesCompleted)", systemImage: "flag.checkered", tint: .pink,
                             caption: "\(report.loggedEntries) entries logged")
                }

                if report.totalFocusSeconds > 0 {
                    FocusChart(report: report)
                    HStack(alignment: .top, spacing: 16) {
                        WeekdayChart(report: report)
                        HourChart(report: report)
                    }
                }
                ScoresCard(report: report)
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(primary: .indigo, secondary: .pink))
        .navigationTitle("Insights")
    }
}

private struct FocusChart: View {
    @Environment(GoalStore.self) private var store
    let report: InsightsReport

    var body: some View {
        let goals = Dictionary(store.data.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let names = report.focusByDay.compactMap { goals[$0.goalID]?.name }
        let order = Array(NSOrderedSet(array: names)) as? [String] ?? []
        let colors = order.map { name in store.data.goals.first { $0.name == name }?.tint ?? .accentColor }
        VStack(alignment: .leading, spacing: 12) {
            Label("Focus time per day", systemImage: "chart.bar.fill")
                .font(.headline)
            Chart(report.focusByDay) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Hours", day.seconds / 3600)
                )
                .foregroundStyle(by: .value("Goal", goals[day.goalID]?.name ?? "Goal"))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: order, range: colors)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) { Text(Formatting.duration(hours * 3600)) }
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 230)
        }
        .glassCard(tint: .indigo)
    }
}

private struct WeekdayChart: View {
    let report: InsightsReport

    var body: some View {
        let symbols = Calendar.current.shortWeekdaySymbols
        let order = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
        let buckets = order.compactMap { day in report.focusByWeekday.first { $0.index == day } }
        let best = buckets.max { $0.seconds < $1.seconds }
        VStack(alignment: .leading, spacing: 12) {
            Label("By weekday", systemImage: "calendar")
                .font(.headline)
            if let best, best.seconds > 0 {
                Text("\(Calendar.current.weekdaySymbols[best.index - 1])s are your strongest days.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Weekday", symbols[bucket.index - 1]),
                    y: .value("Hours", bucket.seconds / 3600)
                )
                .foregroundStyle(bucket.index == best?.index ? AnyShapeStyle(Color.indigo.gradient) : AnyShapeStyle(Color.indigo.opacity(0.35)))
                .cornerRadius(5)
            }
            .chartYAxis(.hidden)
            .frame(height: 160)
        }
        .glassCard(tint: .indigo)
    }
}

private struct HourChart: View {
    let report: InsightsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Time of day", systemImage: "clock")
                .font(.headline)
            if let peak = report.peakHour {
                let start = Calendar.current.date(bySettingHour: peak, minute: 0, second: 0, of: .now) ?? .now
                Text("You focus best around \(start.formatted(date: .omitted, time: .shortened)).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Chart(report.focusByHour) { bucket in
                AreaMark(
                    x: .value("Hour", bucket.index),
                    y: .value("Hours", bucket.seconds / 3600)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [.pink.opacity(0.55), .pink.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("Hour", bucket.index),
                    y: .value("Hours", bucket.seconds / 3600)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.pink)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self) { Text(hour == 0 ? "12a" : hour < 12 ? "\(hour)a" : hour == 12 ? "12p" : "\(hour - 12)p") }
                    }
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 160)
        }
        .glassCard(tint: .pink)
    }
}

private struct ScoresCard: View {
    @Environment(GoalStore.self) private var store
    let report: InsightsReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Goals", systemImage: "list.bullet.rectangle")
                .font(.headline)
            if report.scores.isEmpty {
                Text("Add a goal to see how it's going.")
                    .foregroundStyle(.secondary)
            }
            ForEach(report.scores) { score in
                if let goal = store.goal(score.goalID) {
                    HStack(spacing: 12) {
                        GoalIcon(goal: goal, size: 30)
                        Text(goal.name)
                            .font(.body.weight(.medium))
                            .frame(width: 180, alignment: .leading)
                            .lineLimit(1)
                        ProgressBar(progress: score.completion ?? store.engine.progress(for: goal, now: store.now), color: goal.color, height: 8)
                        Text(score.completion.map { Formatting.percent($0) } ?? Formatting.percent(store.engine.progress(for: goal, now: store.now)))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                        StreakBadge(count: score.streak, unit: score.streakUnit)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.select(goal.id) }
                }
            }
        }
        .glassCard(tint: .accentColor)
    }
}
