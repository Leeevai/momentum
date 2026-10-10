import MomentumCore
import SwiftUI
import WidgetKit

@main
struct MomentumWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        GoalWidget()
        ChallengeWidget()
        MoodWidget()
        WeekWidget()
        FocusWidget()
        StreaksWidget()
        #if os(iOS)
        TodayAccessoryWidget()
        FocusLiveActivity()
        #endif
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 18.0, *) {
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

    /// The palette chosen in the app, built-in or custom.
    var palette: Palette { ActivePalette.current }

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
        let stored = SharedStore.load()
        let data = preview && stored.goals.isEmpty ? .demo() : stored
        ActivePalette.current = data.preferences.activePalette
        return data
    }

    static func entry(preview: Bool, goalID: UUID? = nil) -> MomentumEntry {
        MomentumEntry(date: .now, engine: ProgressEngine(data: data(preview: preview)), goalID: goalID)
    }

    /// Entries at the moments rings need to move; see `WidgetSchedule`.
    static func timeline(goalID: UUID? = nil, now: Date = .now) -> Timeline<MomentumEntry> {
        let engine = ProgressEngine(data: SharedStore.load())
        ActivePalette.current = engine.data.preferences.activePalette
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
/// Drawn as of `now`, the entry's date: WidgetKit draws entries before they're shown, so an entry
/// after the planned end, drawn before it, would otherwise keep a countdown stuck at 0:00.
struct WidgetSessionClock: View {
    let session: FocusSession
    let now: Date

    var body: some View {
        if let reference = session.counterReferenceDate {
            if let end = session.plannedEnd, end > now {
                Text(timerInterval: now...end, countsDown: true)
            } else {
                Text(reference, style: .timer)
            }
        } else {
            Text(Formatting.clock(session.remaining(at: now).map { max(0, $0) } ?? session.elapsed(at: now)))
        }
    }
}

/// The goal's one-tap action as a round button.
struct WidgetActionButton: View {
    let goal: Goal
    let engine: ProgressEngine
    /// The entry's date, for the checkmark: the midnight entry is drawn the day before.
    let now: Date
    var size: CGFloat = 26

    var body: some View {
        Group {
            if goal.kind == .time {
                if engine.isRunning(goal) {
                    Button(intent: StopSessionIntent(goalID: goal.id)) { icon("stop.fill") }
                } else {
                    Button(intent: StartSessionIntent(goalID: goal.id)) { icon("play.fill") }
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
        default: engine.isComplete(goal, now: now) ? "checkmark" : "plus"
        }
    }

    private func icon(_ name: String) -> some View {
        WidgetFilledLabel(fill: goal.color.fill, tint: goal.color.swatch, shape: Circle()) {
            Image(systemName: name)
                .font(.system(size: size * 0.4, weight: .bold))
                .frame(width: size, height: size)
        }
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
                if engine.isRunning(goal) {
                    Button(intent: StopSessionIntent(goalID: goal.id)) { label("Stop", "stop.fill") }
                } else {
                    Button(intent: StartSessionIntent(goalID: goal.id)) {
                        label(goal.focusMinutes.map { "\($0)m focus" } ?? "Start", "play.fill")
                    }
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
        WidgetFilledLabel(fill: goal.color.fill, tint: goal.color.swatch, shape: Capsule()) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
        }
    }
}

/// A label on a filled shape, glasscn's filled button: in full color, white or black on the fill,
/// whichever contrasts more with `tint`, the fill's color. When the system draws widgets in one
/// tint (the faded desktop, tinted Home Screens), the fill becomes a translucent wash with the
/// label over it, rather than one shape the label disappears into.
struct WidgetFilledLabel<S: InsettableShape, Fill: ShapeStyle, Content: View>: View {
    let fill: Fill
    let tint: Color
    let shape: S
    @ViewBuilder var content: Content
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.self) private var environment

    var body: some View {
        if renderingMode == .fullColor {
            content
                .foregroundStyle(tint.foreground(in: environment))
                .background(shape.fill(fill).overlay(shape.strokeBorder(.white.opacity(0.3), lineWidth: 0.5)))
        } else {
            content
                .foregroundStyle(.primary)
                .background(shape.fill(tint.opacity(0.3)).widgetAccentable())
        }
    }
}

/// The goal's ring with its icon and today's amount, or the live session clock.
struct WidgetGoalRing: View {
    let goal: Goal
    let engine: ProgressEngine
    let now: Date
    var lineWidth: CGFloat = 8

    var body: some View {
        ProgressRing(progress: engine.ringProgress(for: goal, now: now), color: goal.color, lineWidth: lineWidth) {
            VStack(spacing: 0) {
                GoalGlyph(goal: goal, size: lineWidth * 2.2)
                Group {
                    if let session = engine.data.session, session.goalID == goal.id {
                        WidgetSessionClock(session: session, now: now)
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
    /// No background of its own: Lock Screen widgets sit on the wallpaper.
    func accessoryBackground() -> some View {
        containerBackground(for: .widget) { Color.clear }
    }

    /// Widget background: the palette's aurora, standing still, with `accent` (a goal's color) in
    /// it when the widget is about one thing. The view is drawn in the palette too.
    func widgetBackground(for entry: MomentumEntry, accent: Color? = nil) -> some View {
        containerBackground(for: .widget) {
            Aurora(accent: accent, animates: false, scale: 0.3)
        }
        .palette(entry.palette)
    }
}

extension Image {
    /// Keeps a photo (a book cover) a photo, desaturated, when the system draws widgets in one
    /// tint, instead of filling it in as a single shape.
    @ViewBuilder
    func keepsPhoto() -> some View {
        if #available(macOS 15.0, iOS 18.0, *) {
            widgetAccentedRenderingMode(.desaturated)
        } else {
            self
        }
    }
}
