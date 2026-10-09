import MomentumCore
import SwiftUI
import WidgetKit

/// The focus timer: live countdown with pause and stop, or one-tap starts when idle.
struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Focus", provider: TodayProvider()) { entry in
            FocusWidgetView(entry: entry)
                .widgetBackground(entry.data.session.flatMap { entry.engine.goal($0.goalID)?.tint } ?? .indigo)
        }
        .configurationDisplayName("Focus")
        .description("A live focus timer you can pause and stop, or start in one click.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomentumEntry

    var body: some View {
        let engine = entry.engine
        if let session = entry.data.session, let goal = engine.goal(session.goalID) {
            running(session: session, goal: goal)
        } else {
            idle(goals: entry.filtered(engine.activeGoals).filter { $0.kind == .time && !$0.isOnBreak(at: entry.date) })
        }
    }

    private func running(session: FocusSession, goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(goal.name, systemImage: goal.symbol)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(session.isRunning ? (session.plannedDuration == nil ? "FOCUS" : "LEFT") : "PAUSED")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(goal.tint)
            }
            WidgetSessionClock(session: session)
                .font(.system(size: family == .systemSmall ? 34 : 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(goal.color.linear)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let planned = session.plannedDuration {
                ProgressBar(progress: session.elapsed(at: entry.date) / planned, color: goal.color, height: 5)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(intent: SetPausedIntent(paused: session.isRunning)) {
                    Label(session.isRunning ? "Pause" : "Resume", systemImage: session.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(goal.tint.opacity(0.18)))
                }
                Button(intent: StopSessionIntent(goalID: goal.id)) {
                    Label("Stop", systemImage: "stop.fill")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(goal.color.linear))
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .labelStyle(family == .systemSmall ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        }
        .widgetURL(DeepLink.goal(goal.id).url)
    }

    @ViewBuilder
    private func idle(goals: [Goal]) -> some View {
        if goals.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.title)
                    .foregroundStyle(.indigo)
                Text("Add a time goal to focus from here.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .widgetURL(DeepLink.newGoal.url)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Start a focus session", systemImage: "timer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(goals.prefix(family == .systemSmall ? 2 : 3)) { goal in
                    Button(intent: StartSessionIntent(goalID: goal.id)) {
                        HStack(spacing: 8) {
                            GoalGlyph(goal: goal, size: 13)
                            Text(goal.name)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if family != .systemSmall {
                                Text(goal.focusMinutes.map { "\($0)m" } ?? "∞")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "play.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(goal.tint)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(goal.tint.opacity(0.13)))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .widgetURL(DeepLink.today.url)
        }
    }
}

/// Type-erased label style, so the label style can depend on the widget size.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init<Style: LabelStyle>(_ style: Style) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

/// Every goal's current streak, longest first.
struct StreaksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Streaks", provider: TodayProvider()) { entry in
            StreaksWidgetView(entry: entry)
                .widgetBackground(.orange)
                .widgetURL(DeepLink.insights.url)
        }
        .configurationDisplayName("Streaks")
        .description("Your streaks at a glance. Don't break the chain.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StreaksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomentumEntry

    var body: some View {
        let engine = entry.engine
        let ranked = entry.filtered(engine.activeGoals)
            .map { ($0, engine.streak(for: $0, now: entry.date)) }
            .sorted { $0.1.current > $1.1.current }
        if ranked.isEmpty {
            WidgetEmptyView()
        } else if family == .systemSmall, let top = ranked.first {
            VStack(alignment: .leading, spacing: 4) {
                Label("Longest streak", systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer(minLength: 0)
                Text("\(top.1.current)")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
                    .minimumScaleFactor(0.5)
                Text("\(Formatting.unit("\(top.1.unit)s", for: Double(top.1.current))) of \(top.0.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Label("Streaks", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                let best = max(1, ranked.first?.1.best ?? 1)
                ForEach(ranked.prefix(family == .systemLarge ? 8 : 3), id: \.0.id) { goal, streak in
                    HStack(spacing: 8) {
                        GoalGlyph(goal: goal, size: 13)
                        Text(goal.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .frame(width: family == .systemLarge ? 130 : 110, alignment: .leading)
                        ProgressBar(progress: Double(streak.current) / Double(max(best, streak.best)), color: goal.color, height: 6)
                        Text("\(streak.current)\(streak.unit.prefix(1))")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
