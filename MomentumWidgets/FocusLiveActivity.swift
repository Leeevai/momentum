#if os(iOS)
import ActivityKit
import MomentumCore
import SwiftUI
import WidgetKit

/// The running focus timer, or a Pomodoro break, on the Lock Screen and in the Dynamic Island,
/// with pause, stop and next-block buttons.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenFocusView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(DeepLink.today.url)
        } dynamicIsland: { context in
            let attributes = context.attributes
            let state = context.state
            let tint = attributes.tint
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityGlyph(attributes: attributes, state: state, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityClock(state: state, isStale: context.isStale)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .frame(maxWidth: 120, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(state.phaseTitle(isStale: context.isStale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                        Text(attributes.goalName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        ActivityProgress(state: state, tint: tint)
                        ActivityButtons(attributes: attributes, state: state)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.phase == .resting ? "leaf.fill" : attributes.symbol)
                    .foregroundStyle(tint)
            } compactTrailing: {
                ActivityClock(state: state, isStale: context.isStale)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: state.phase == .resting ? "leaf.fill" : attributes.symbol)
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
            .widgetURL(DeepLink.today.url)
        }
    }
}

private struct LockScreenFocusView: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ActivityGlyph(attributes: attributes, state: state, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.phaseTitle(isStale: isStale))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(attributes.tint)
                    Text(attributes.goalName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                ActivityClock(state: state, isStale: isStale)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            HStack(spacing: 12) {
                ActivityProgress(state: state, tint: attributes.tint)
                ActivityButtons(attributes: attributes, state: state)
            }
        }
    }
}

/// The goal's symbol on its color; a leaf during a break.
private struct ActivityGlyph: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Image(systemName: state.phase == .resting ? "leaf.fill" : attributes.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(attributes.goalColor.linear))
            .opacity(state.phase == .paused ? 0.6 : 1)
    }
}

/// Counts down to the planned end and then on into overtime, up from the start when open-ended,
/// and holds still when paused.
private struct ActivityClock: View {
    let state: FocusActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Group {
            if state.phase == .paused {
                Text(Formatting.clock(state.remaining ?? state.elapsed))
            } else if let end = state.end, isStale || end <= .now {
                if state.phase == .resting {
                    Text("0:00")
                } else {
                    // Past the planned end: the overtime, counting up, as the app shows it.
                    Text("+") + Text(end, style: .timer)
                }
            } else if let end = state.end {
                Text(timerInterval: state.counterStart...max(end, state.counterStart), countsDown: true)
            } else {
                Text(state.counterStart, style: .timer)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

/// How far through the block or break; nothing for an open-ended session.
private struct ActivityProgress: View {
    let state: FocusActivityAttributes.ContentState
    let tint: Color

    var body: some View {
        if let end = state.end, end > state.counterStart, state.phase != .paused {
            ProgressView(timerInterval: state.counterStart...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(tint)
        } else {
            Spacer(minLength: 0)
        }
    }
}

private struct ActivityButtons: View {
    let attributes: FocusActivityAttributes
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            switch state.phase {
            case .focusing, .paused:
                Button(intent: SetPausedIntent(paused: state.phase != .paused)) {
                    Image(systemName: state.phase == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(ActivityButtonStyle(tint: .white.opacity(0.18)))
                if let id = UUID(uuidString: attributes.goalID) {
                    Button(intent: StopSessionIntent(goalID: id)) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(ActivityButtonStyle(tint: attributes.tint))
                }
            case .resting:
                Button(intent: EndBreakIntent()) {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(ActivityButtonStyle(tint: .white.opacity(0.18)))
                Button(intent: StartNextBlockIntent()) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(ActivityButtonStyle(tint: attributes.tint))
            }
        }
    }
}

private struct ActivityButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 36)
            .background(Capsule().fill(tint))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension FocusActivityAttributes {
    var goalColor: GoalColor { GoalColor(rawValue: color) ?? .indigo }
    var tint: Color { goalColor.color }
}

extension FocusActivityAttributes.ContentState {
    func phaseTitle(isStale: Bool) -> String {
        switch phase {
        case .focusing where isStale && end != nil: "Time's up"
        case .focusing: block.map { "Block \($0)" } ?? "Focusing"
        case .paused: "Paused"
        case .resting where isStale: "Break's over"
        case .resting: "Break · block \(block ?? 1) next"
        }
    }
}

// MARK: - Lock Screen widgets

/// Today's progress on the Lock Screen: a ring, a line, or a sentence.
struct TodayAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayAccessory", provider: TodayProvider()) { entry in
            TodayAccessoryView(entry: entry)
                .widgetURL(DeepLink.today.url)
        }
        .configurationDisplayName("Today at a Glance")
        .description("How many of today's goals are done, and your best streak.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct TodayAccessoryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomentumEntry

    var body: some View {
        let engine = entry.engine
        let summary = engine.todaySummary(now: entry.date)
        let streak = engine.longestCurrentStreak(now: entry.date)
        let fraction = summary.total == 0 ? 0 : Double(summary.done) / Double(summary.total)
        switch family {
        case .accessoryCircular:
            Gauge(value: fraction) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(summary.done)/\(summary.total)")
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessoryBackground()
        case .accessoryInline:
            Label("\(summary.done) of \(summary.total) done · \(streak)-day streak", systemImage: "flame.fill")
                .accessoryBackground()
        default:
            VStack(alignment: .leading, spacing: 3) {
                Label("Momentum", systemImage: "flame.fill")
                    .font(.headline)
                    .widgetAccentable()
                if let session = entry.data.session, let goal = engine.goal(session.goalID) {
                    HStack(spacing: 4) {
                        Text(goal.name).lineLimit(1)
                        WidgetSessionClock(session: session)
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                } else {
                    Text("\(summary.done) of \(summary.total) done today")
                        .font(.subheadline.weight(.semibold))
                }
                Gauge(value: fraction) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessoryBackground()
        }
    }
}
#endif
