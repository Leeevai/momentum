import MomentumCore
import SwiftUI
import WidgetKit

/// Every goal due today, each with its one-tap action.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetBackground(.blue)
                .widgetURL(DeepLink.today.url)
        }
        .configurationDisplayName("Today")
        .description("Today's goals and streaks, with one-click timers, check-ins and page logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> MomentumEntry {
        MomentumEntry(date: .now, engine: ProgressEngine(data: .demo()))
    }

    func getSnapshot(in context: Context, completion: @escaping (MomentumEntry) -> Void) {
        completion(WidgetTimeline.entry(preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MomentumEntry>) -> Void) {
        completion(WidgetTimeline.timeline())
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomentumEntry

    var body: some View {
        if entry.engine.activeGoals.isEmpty {
            WidgetEmptyView()
        } else if family == .systemSmall {
            TodaySmall(entry: entry)
        } else {
            TodayList(entry: entry, maxRows: family == .systemLarge ? 5 : 3, showsWeek: family == .systemLarge)
        }
    }
}

private struct TodaySmall: View {
    let entry: MomentumEntry

    var body: some View {
        let engine = entry.engine
        let summary = engine.todaySummary(now: entry.date)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                StreakBadge(count: engine.longestCurrentStreak(now: entry.date))
            }
            Spacer(minLength: 4)
            if let session = entry.data.session, let goal = engine.goal(session.goalID) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(goal.name, systemImage: goal.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    WidgetSessionClock(session: session)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(goal.color.linear)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer(minLength: 2)
                    HStack(spacing: 6) {
                        Button(intent: SetPausedIntent(paused: session.isRunning)) {
                            Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(goal.tint.opacity(0.18)))
                        }
                        WidgetWideButton(goal: goal, engine: engine)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                }
            } else {
                let fraction = summary.total == 0 ? 0 : Double(summary.done) / Double(summary.total)
                HStack(alignment: .center, spacing: 10) {
                    ProgressRing(progress: fraction, color: .blue, lineWidth: 9) {
                        Text("\(summary.done)/\(summary.total)")
                            .font(.system(.headline, design: .rounded))
                            .monospacedDigit()
                    }
                    .frame(width: 78, height: 78)
                }
                Spacer(minLength: 4)
                Text(summary.total == 0 ? "Nothing due" : summary.done == summary.total ? "All done" : "\(summary.total - summary.done) to go")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TodayList: View {
    let entry: MomentumEntry
    let maxRows: Int
    let showsWeek: Bool

    var body: some View {
        let engine = entry.engine
        let goals = entry.filtered(engine.todayGoals(now: entry.date))
            .sorted { lhs, rhs in
                let left = engine.isRunning(lhs) ? 0 : (engine.isComplete(lhs, now: entry.date) ? 2 : 1)
                let right = engine.isRunning(rhs) ? 0 : (engine.isComplete(rhs, now: entry.date) ? 2 : 1)
                return left < right
            }
        let summary = engine.todaySummary(now: entry.date)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.headline)
                Spacer()
                Text("\(summary.done) of \(summary.total) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if goals.isEmpty {
                Text("Nothing due today. Enjoy it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(goals.prefix(maxRows)) { goal in
                TodayRow(goal: goal, entry: entry)
            }
            if goals.count > maxRows {
                Text("+\(goals.count - maxRows) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if showsWeek {
                WeekGrid(engine: engine, goals: Array(goals.prefix(4)), now: entry.date)
            }
        }
    }
}

private struct TodayRow: View {
    let goal: Goal
    let entry: MomentumEntry

    var body: some View {
        let engine = entry.engine
        let streak = engine.streak(for: goal, now: entry.date)
        HStack(spacing: 8) {
            Link(destination: DeepLink.goal(goal.id).url) {
                row(engine: engine, streak: streak)
            }
            WidgetActionButton(goal: goal, engine: engine)
        }
    }

    private func row(engine: ProgressEngine, streak: ProgressEngine.Streak) -> some View {
        HStack(spacing: 10) {
            ProgressRing(progress: engine.progress(for: goal, now: entry.date), color: goal.color, lineWidth: 4) {
                GoalGlyph(goal: goal, size: 11)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(goal.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let session = entry.data.session, session.goalID == goal.id {
                    WidgetSessionClock(session: session)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(goal.tint)
                } else {
                    Text(goal.progressText(engine.currentAmount(for: goal, now: entry.date), target: engine.target(for: goal)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            StreakBadge(count: streak.current, unit: streak.unit)
        }
    }
}

/// This week at a glance: one dot per goal per day.
private struct WeekGrid: View {
    let engine: ProgressEngine
    let goals: [Goal]
    let now: Date

    var body: some View {
        let days = Heatmap.weeks(1, endingAt: now, engine: engine)[0]
        let symbols = engine.calendar.veryShortWeekdaySymbols
        let today = engine.startOfDay(now)
        VStack(alignment: .leading, spacing: 5) {
            Text("This week")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Grid(horizontalSpacing: 0, verticalSpacing: 5) {
                GridRow {
                    Color.clear.frame(width: 22, height: 1)
                    ForEach(days.indices, id: \.self) { index in
                        let weekday = (engine.calendar.firstWeekday - 1 + index) % 7 + 1
                        Text(symbols[weekday - 1])
                            .font(.caption2.weight(days[index] == today ? .bold : .regular))
                            .foregroundStyle(days[index] == today ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(goals) { goal in
                    GridRow {
                        GoalGlyph(goal: goal, size: 10)
                            .frame(width: 22, alignment: .leading)
                        ForEach(days.indices, id: \.self) { index in
                            dot(goal, days[index])
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dot(_ goal: Goal, _ day: Date?) -> some View {
        if let day {
            let intensity = engine.intensity(for: goal, on: day, now: now)
            if intensity >= 1 {
                Circle().fill(goal.color.linear).frame(width: 11, height: 11)
            } else if intensity > 0 {
                Circle().fill(goal.tint.opacity(0.4)).frame(width: 11, height: 11)
            } else if engine.isRequired(goal, on: day) {
                Circle().strokeBorder(goal.tint.opacity(0.5), lineWidth: 1.5).frame(width: 11, height: 11)
            } else {
                Circle().fill(Color.primary.opacity(0.08)).frame(width: 5, height: 5)
            }
        } else {
            Circle().fill(Color.primary.opacity(0.08)).frame(width: 5, height: 5)
        }
    }
}
