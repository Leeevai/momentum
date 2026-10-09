import MomentumCore
import SwiftUI
import WidgetKit

@main
struct MomentumWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        GoalWidget()
        FocusWidget()
        StreaksWidget()
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            FocusControl()
        }
        #endif
    }
}

struct MomentumEntry: TimelineEntry {
    let date: Date
    let engine: ProgressEngine
    var goalID: UUID?
    /// The current macOS Focus's filter, for the list widgets.
    var focusFilter: FocusFilter? = SharedStore.loadFocusFilter()

    var data: AppData { engine.data }

    /// `goals` narrowed by the Focus filter, keeping a running timer's goal.
    func filtered(_ goals: [Goal]) -> [Goal] {
        focusFilter?.apply(to: goals, session: data.session) ?? goals
    }

    /// The configured goal, or the first active one.
    var goal: Goal? {
        goalID.flatMap(engine.goal) ?? engine.activeGoals.first
    }
}

enum WidgetTimeline {
    /// Sample data for the gallery, until the user has goals of their own.
    static func data(preview: Bool) -> AppData {
        let data = SharedStore.load()
        return preview && data.goals.isEmpty ? .demo() : data
    }

    static func entry(preview: Bool, goalID: UUID? = nil) -> MomentumEntry {
        MomentumEntry(date: .now, engine: ProgressEngine(data: data(preview: preview)), goalID: goalID)
    }

    /// Entries at the moments rings need to move; see `WidgetSchedule`.
    static func timeline(goalID: UUID? = nil, now: Date = .now) -> Timeline<MomentumEntry> {
        let engine = ProgressEngine(data: SharedStore.load())
        let entries = WidgetSchedule.entryDates(for: engine.data, now: now).map {
            MomentumEntry(date: $0, engine: engine, goalID: goalID)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Shared widget views

struct WidgetEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Open Momentum to add your first goal")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .widgetURL(DeepLink.newGoal.url)
    }
}

/// A running session's clock: a live countdown for planned sessions, a stopwatch otherwise.
struct WidgetSessionClock: View {
    let session: FocusSession

    var body: some View {
        if let reference = session.counterReferenceDate {
            if let end = session.plannedEnd, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true)
            } else {
                Text(reference, style: .timer)
            }
        } else {
            Text(Formatting.clock(session.remaining(at: .now).map { max(0, $0) } ?? session.elapsed(at: .now)))
        }
    }
}

/// The goal's one-tap action as a round button.
struct WidgetActionButton: View {
    let goal: Goal
    let engine: ProgressEngine
    var size: CGFloat = 26

    var body: some View {
        Group {
            if goal.kind == .time {
                Button(intent: ToggleFocusIntent(goalID: goal.id)) {
                    icon(engine.isRunning(goal) ? "stop.fill" : "play.fill")
                }
            } else if goal.kind == .books && goal.currentBook == nil {
                Link(destination: DeepLink.goal(goal.id).url) { icon("plus") }
            } else {
                Button(intent: QuickAddIntent(goalID: goal.id)) {
                    icon(symbol)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var symbol: String {
        switch goal.kind {
        case .milestones: "checkmark"
        case .books: "book.pages"
        default: engine.isComplete(goal, now: .now) ? "checkmark" : "plus"
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(goal.color.linear))
            .widgetAccentable()
    }
}

/// A full-width capsule version of the action.
struct WidgetWideButton: View {
    let goal: Goal
    let engine: ProgressEngine

    var body: some View {
        Group {
            switch goal.kind {
            case .time:
                let running = engine.isRunning(goal)
                Button(intent: ToggleFocusIntent(goalID: goal.id)) {
                    label(running ? "Stop" : (goal.focusMinutes.map { "\($0)m focus" } ?? "Start"), running ? "stop.fill" : "play.fill")
                }
            case .books:
                if goal.currentBook != nil {
                    Button(intent: QuickAddIntent(goalID: goal.id)) { label("+\(Int(goal.quickAddStep)) pages", "book.pages") }
                } else {
                    Link(destination: DeepLink.goal(goal.id).url) { label("Add book", "plus") }
                }
            case .milestones:
                Button(intent: QuickAddIntent(goalID: goal.id)) { label("Done", "checkmark") }
                    .disabled(!goal.milestones.contains { !$0.isDone })
            case .count, .amount:
                Button(intent: QuickAddIntent(goalID: goal.id)) {
                    label(goal.kind == .count && goal.quickAddStep == 1 ? "Log" : "+\(goal.format(goal.quickAddStep))", "plus")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func label(_ title: String, _ systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Capsule().fill(goal.color.linear))
            .widgetAccentable()
    }
}

/// The goal's ring with its icon and today's amount, or the live session clock.
struct WidgetGoalRing: View {
    let goal: Goal
    let engine: ProgressEngine
    let now: Date
    var lineWidth: CGFloat = 8

    var body: some View {
        ProgressRing(progress: engine.progress(for: goal, now: now), color: goal.color, lineWidth: lineWidth) {
            VStack(spacing: 0) {
                Text(goal.icon)
                    .font(.system(size: lineWidth * 2.4))
                Group {
                    if let session = engine.data.session, session.goalID == goal.id {
                        WidgetSessionClock(session: session)
                    } else {
                        Text(goal.formatShort(engine.currentAmount(for: goal, now: now)))
                    }
                }
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            }
            .padding(lineWidth)
        }
    }
}

extension View {
    /// Widget background: a soft gradient tinted by `tint`.
    func widgetBackground(_ tint: Color) -> some View {
        containerBackground(for: .widget) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}
