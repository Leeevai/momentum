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
                             caption: focusCaption(report))
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
                    if report.focusByCategory.count > 1 {
                        CategoryChart(report: report)
                    }
                }
                let mood = engine.moodReport(in: report.range, now: store.now)
                if mood.days >= 3 {
                    MoodCard(report: mood)
                }
                ScoresCard(report: report)
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(LivingBackdrop(primary: .indigo, secondary: .pink))
        .navigationTitle("Insights")
    }

    /// "▲ 12% vs the 30 days before", or the daily average without a baseline.
    private func focusCaption(_ report: InsightsReport) -> String {
        guard let change = report.focusChange else {
            return "\(Formatting.duration(report.averageFocusPerDay)) a day on average"
        }
        let arrow = change > 0.005 ? "▲" : (change < -0.005 ? "▼" : "=")
        let span = days == 365 ? "year" : "\(days) days"
        return "\(arrow) \(Formatting.percent(abs(change))) vs the \(span) before"
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

/// Where the focus time went, by category.
private struct CategoryChart: View {
    let report: InsightsReport
    @State private var selectedAngle: Double?

    private static let palette: [Color] = [.indigo, .orange, .teal, .pink, .green, .purple, .yellow, .blue, .red, .mint]

    var body: some View {
        let shares = report.focusByCategory
        let selected = selectedAngle.flatMap { angle -> InsightsReport.CategoryShare? in
            var running = 0.0
            return shares.first { share in
                running += share.seconds
                return angle <= running
            }
        }
        HStack(alignment: .center, spacing: 28) {
            Chart(shares) { share in
                SectorMark(
                    angle: .value("Time", share.seconds),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Category", share.name))
                .opacity(selected == nil || selected?.name == share.name ? 1 : 0.4)
            }
            .chartForegroundStyleScale(domain: shares.map(\.name), range: shares.indices.map { Self.palette[$0 % Self.palette.count] })
            .chartLegend(.hidden)
            .chartAngleSelection(value: $selectedAngle)
            .chartBackground { _ in
                VStack(spacing: 2) {
                    Text(selected.map { Formatting.duration($0.seconds) } ?? Formatting.duration(report.totalFocusSeconds))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(selected?.name ?? "total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 190, height: 190)

            VStack(alignment: .leading, spacing: 10) {
                Label("By category", systemImage: "chart.pie.fill")
                    .font(.headline)
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Self.palette[index % Self.palette.count])
                            .frame(width: 9, height: 9)
                        Text(share.name)
                            .frame(minWidth: 110, alignment: .leading)
                        Text(Formatting.duration(share.seconds))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(Formatting.percent(share.seconds / max(1, report.totalFocusSeconds)))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    .font(.callout)
                }
            }
            Spacer(minLength: 0)
        }
        .glassCard(tint: .indigo)
    }
}

/// How mood lines up with progress and focus, from the journal.
private struct MoodCard: View {
    let report: MoodReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Mood and momentum", systemImage: "cloud.sun.fill")
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            Text(headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 18) {
                if let good = report.moodOnGoodDays {
                    MoodColumn(title: "Days most goals were done", value: good)
                }
                if let other = report.moodOnOtherDays {
                    MoodColumn(title: "Other days", value: other)
                }
                Divider().frame(height: 80)
                Chart(Mood.allCases) { mood in
                    BarMark(x: .value("Mood", mood.title), y: .value("Focus", (report.focusByMood[mood] ?? 0) / 3600))
                        .foregroundStyle(mood.tint.gradient)
                        .cornerRadius(5)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel { Text("\(value.as(Double.self).map { Formatting.number($0) } ?? "")h") }
                    }
                }
                .frame(height: 120)
                .overlay(alignment: .topTrailing) {
                    Text("Average focus by mood")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCard(cornerRadius: 22)
    }

    private var headline: String {
        guard let good = report.moodOnGoodDays, let other = report.moodOnOtherDays else {
            return "Rate more days in the journal to see how mood and progress relate."
        }
        let difference = good - other
        if difference > 0.3 { return "You feel better on days you get through your goals: \(Self.describe(good)) versus \(Self.describe(other))." }
        if difference < -0.3 { return "Your mood runs higher on lighter days. Maybe the targets are asking a lot." }
        return "Your mood holds steady whether or not the goals get done."
    }

    static func describe(_ value: Double) -> String {
        let mood = Mood(rawValue: Int(value.rounded())) ?? .okay
        return "\(mood.title.lowercased()) (\(String(format: "%.1f", value)))"
    }

    private struct MoodColumn: View {
        let title: String
        let value: Double

        var body: some View {
            let mood = Mood(rawValue: Int(value.rounded())) ?? .okay
            VStack(spacing: 8) {
                Image(systemName: mood.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 34))
                    .foregroundStyle(mood.tint)
                Text(String(format: "%.1f", value))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 110)
            }
        }
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
