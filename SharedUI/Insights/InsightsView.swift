import Charts
import MomentumCore
import SwiftUI

struct InsightsView: View {
    @Environment(GoalStore.self) private var store
    @State private var days = 30

    var body: some View {
        let engine = store.engine
        let report = engine.insights(days: days, now: store.now)
        let quality = engine.focusQualityReport(in: report.range)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        titles
                        Spacer()
                        rangePicker.frame(width: 300)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        titles
                        rangePicker
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
                    StatTile(title: "Focused", value: Formatting.duration(report.totalFocusSeconds), systemImage: "timer", tint: .focus,
                             caption: focusCaption(report))
                    StatTile(title: "Active days", value: "\(report.activeDays) of \(days)", systemImage: "calendar.badge.checkmark", tint: .success,
                             caption: Formatting.percent(Double(report.activeDays) / Double(days)) + " of days")
                    let streaks = engine.activeGoals.map { ($0, engine.streak(for: $0, now: store.now)) }
                    let longest = streaks.max { $0.1.current < $1.1.current }
                    StatTile(title: "Best streak now", value: "\(longest?.1.current ?? 0)", systemImage: "flame.fill", tint: .streak,
                             caption: longest.flatMap { $0.1.current > 0 ? $0.0.name : nil })
                    StatTile(title: "Books finished", value: "\(report.booksFinished)", systemImage: "books.vertical.fill", tint: .swatch(.brown),
                             caption: "\(Formatting.number(report.pagesRead)) pages read")
                    StatTile(title: "Milestones", value: "\(report.milestonesCompleted)", systemImage: "flag.checkered", tint: .swatch(.pink),
                             caption: "\(report.loggedEntries) entries logged")
                    if let flow = quality.flowShare {
                        StatTile(title: "In the flow", value: Formatting.percent(flow), systemImage: "water.waves", tint: .focus,
                                 caption: "of rated focus")
                    } else {
                        StatTile(title: "Daily focus", value: Formatting.duration(report.averageFocusPerDay), systemImage: "sun.max.fill", tint: .swatch(.yellow),
                                 caption: "on average")
                    }
                }

                if report.totalFocusSeconds > 0 {
                    FocusChart(report: report)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)], spacing: 16) {
                        WeekdayChart(report: report)
                        HourChart(report: report)
                    }
                    if report.focusByCategory.count > 1 {
                        CategoryChart(report: report)
                    }
                    if quality.ratedSessions > 0 {
                        FocusQualityCard(report: quality)
                    }
                }
                let mood = engine.moodReport(in: report.range, now: store.now)
                if mood.days >= 3 {
                    MoodCard(report: mood)
                }
                ScoresCard(report: report)
            }
            .padding(Metrics.screenPadding)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(Aurora())
        .navigationTitle("Insights")
    }

    @ViewBuilder
    private var titles: some View {
        VStack(alignment: .leading, spacing: 4) {
            if Metrics.showsInlineTitles {
                Text("Insights")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            Text("How the last \(days) days went.")
                .foregroundStyle(.secondary)
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: $days.animation(.easeInOut)) {
            Text("7 days").tag(7)
            Text("30 days").tag(30)
            Text("90 days").tag(90)
            Text("Year").tag(365)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    /// "▲ 12% vs before" (the same number of days before), or the daily average without a baseline.
    private func focusCaption(_ report: InsightsReport) -> String {
        guard let change = report.focusChange else {
            return "\(Formatting.duration(report.averageFocusPerDay)) a day on average"
        }
        let arrow = change > 0.005 ? "▲" : (change < -0.005 ? "▼" : "=")
        return "\(arrow) \(Formatting.percent(abs(change))) vs before"
    }
}

private struct FocusChart: View {
    @Environment(GoalStore.self) private var store
    let report: InsightsReport

    var body: some View {
        let goals = Dictionary(store.data.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let names = report.focusByDay.compactMap { goals[$0.goalID]?.name }
        let order = Array(NSOrderedSet(array: names)) as? [String] ?? []
        let colors = order.map { name in store.data.goals.first { $0.name == name }?.tint ?? .accent }
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
        .glassCard(tint: .focus)
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
                .foregroundStyle(bucket.index == best?.index ? AnyShapeStyle(Color.focus.gradient) : AnyShapeStyle(Color.focus.opacity(0.35)))
                .cornerRadius(5)
            }
            .chartYAxis(.hidden)
            .frame(height: 160)
        }
        .glassCard(tint: .focus)
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
                .foregroundStyle(LinearGradient(colors: [Color.swatch(.pink).opacity(0.55), Color.swatch(.pink).opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("Hour", bucket.index),
                    y: .value("Hours", bucket.seconds / 3600)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.swatch(.pink))
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
        .glassCard(tint: .swatch(.pink))
    }
}

/// How rated sessions went: a bar split by rating, and the hour they go best.
private struct FocusQualityCard: View {
    let report: FocusQualityReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Focus quality", systemImage: "water.waves")
                .font(.headline)
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(FocusQuality.allCases.reversed()) { quality in
                        let share = (report.seconds[quality] ?? 0) / max(report.ratedSeconds, 1)
                        if share > 0 {
                            Capsule()
                                .fill(quality.tint.gradient)
                                .frame(width: max(6, (proxy.size.width - 6) * share))
                        }
                    }
                }
            }
            .frame(height: 14)
            HStack(spacing: 18) {
                ForEach(FocusQuality.allCases.reversed()) { quality in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(quality.title, systemImage: quality.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(quality.tint)
                        Text(Formatting.duration(report.seconds[quality] ?? 0))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .focus)
    }

    private var summary: String {
        var parts: [String] = []
        if let share = report.flowShare {
            parts.append("In the flow for \(Formatting.percent(share)) of rated focus, over \(report.ratedSessions) \(report.ratedSessions == 1 ? "session" : "sessions").")
        }
        if let hour = report.bestHour {
            let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
            parts.append("Your sessions go best around \(start.formatted(date: .omitted, time: .shortened)).")
        } else {
            parts.append("Rate a few more to learn when yours go best.")
        }
        return parts.joined(separator: " ")
    }
}

/// Where the focus time went, by category.
private struct CategoryChart: View {
    let report: InsightsReport
    @State private var selectedAngle: Double?

    /// Categories in the palette's goal colors, in an order that keeps neighbors apart.
    private static var palette: [Color] {
        ([.indigo, .orange, .teal, .pink, .green, .purple, .yellow, .blue, .red, .mint] as [GoalColor]).map(\.color)
    }

    var body: some View {
        let shares = report.focusByCategory
        let selected = selectedAngle.flatMap { angle -> InsightsReport.CategoryShare? in
            var running = 0.0
            return shares.first { share in
                running += share.seconds
                return angle <= running
            }
        }
        let chart = Group {
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
        }
        let legend = Group {
            VStack(alignment: .leading, spacing: 10) {
                Label("By category", systemImage: "chart.pie.fill")
                    .font(.headline)
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Self.palette[index % Self.palette.count])
                            .frame(width: 9, height: 9)
                        Text(share.name)
                            .frame(minWidth: 96, alignment: .leading)
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
        }
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 28) {
                chart
                legend
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 18) {
                chart.frame(maxWidth: .infinity)
                legend
            }
        }
        .glassCard(tint: .focus)
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 18) {
                    columns
                    Divider().frame(height: 80)
                    chart.frame(minWidth: 280)
                }
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .bottom, spacing: 18) { columns }
                    chart
                }
            }
        }
        .glassCard(cornerRadius: 22)
    }

    @ViewBuilder
    private var columns: some View {
        if let good = report.moodOnGoodDays {
            MoodColumn(title: "Days most goals were done", value: good)
        }
        if let other = report.moodOnOtherDays {
            MoodColumn(title: "Other days", value: other)
        }
    }

    private var chart: some View {
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
                            .frame(minWidth: 80, maxWidth: 180, alignment: .leading)
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
        .glassCard(tint: .accent)
    }
}
