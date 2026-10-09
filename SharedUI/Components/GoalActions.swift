import MomentumCore
import SwiftUI

/// The primary action for any goal: start/stop focus, log the quick-add step, complete the next
/// milestone, or read pages in the current book.
struct GoalPrimaryButton: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    var compact = false
    var iconOnly = false

    var body: some View {
        Group {
            switch goal.kind {
            case .time:
                FocusControlCluster(goal: goal, compact: compact, iconOnly: iconOnly)
            case .count, .amount:
                button(quickAddTitle, "plus") { store.quickAdd(goal) }
            case .milestones:
                let next = goal.milestones.first { !$0.isDone }
                button(next == nil ? "All done" : "Done", "checkmark") { store.quickAdd(goal) }
                    .disabled(next == nil)
                    .help(next.map { "Complete \"\($0.title)\"" } ?? "Every milestone is done")
            case .books:
                if goal.currentBook != nil {
                    button("+\(Int(goal.quickAddStep)) pages", "book.pages") { store.quickAdd(goal) }
                } else {
                    button("Add book", "plus") { store.sheet = .book(goalID: goal.id, book: nil) }
                }
            }
        }
        .sensoryFeedback(.success, trigger: store.engine.currentAmount(for: goal, now: store.now))
    }

    private var quickAddTitle: String {
        let step = goal.quickAddStep
        return goal.kind == .count && step == 1 ? "Log" : "+\(goal.format(step))"
    }

    @ViewBuilder
    private func button(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        if iconOnly {
            Button(action: action) { Image(systemName: systemImage) }
                .buttonStyle(CircleButtonStyle(tint: goal.tint, size: compact ? 28 : 34))
                .help(title)
                .accessibilityLabel(title)
        } else {
            Button(action: action) { Label(title, systemImage: systemImage) }
                .primaryActionStyle(goal.tint, compact: compact)
        }
    }
}

/// Start, or Pause and Stop: one glass pill that splits in two when a session starts and merges
/// back when it stops (Liquid Glass morphing on macOS 26; a spring cross-fade before).
struct FocusControlCluster: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    var compact = false
    var iconOnly = false
    @Namespace private var glass

    var body: some View {
        let session = store.data.session
        let running = session?.goalID == goal.id
        let ticking = running && session?.isRunning == true
        GlassGroup(spacing: compact ? 6 : 10) {
            HStack(spacing: compact ? 6 : 10) {
                if running {
                    Button {
                        withAnimation(Self.morph) { store.togglePause() }
                    } label: {
                        label(ticking ? "Pause" : "Resume", ticking ? "pause.fill" : "play.fill")
                    }
                    .secondaryActionStyle(goal.tint, compact: compact)
                    .glassMorphID("pause", in: glass)
                    // Slides out of the main pill as the session starts, and back into it on stop.
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.3, anchor: .trailing).combined(with: .opacity).combined(with: .offset(x: 24)),
                        removal: .scale(scale: 0.3, anchor: .trailing).combined(with: .opacity).combined(with: .offset(x: 24))
                    ))
                    .help(ticking ? "Pause" : "Resume")
                }
                Button {
                    withAnimation(Self.morph) { store.toggleFocus(goal) }
                } label: {
                    label(running ? "Stop" : "Start", running ? "stop.fill" : "play.fill")
                }
                .primaryActionStyle(goal.tint, compact: compact)
                .glassMorphID("primary", in: glass)
                .help(running ? "Stop and save" : "Start a focus session")
                .contextMenu { FocusLengthMenu(goal: goal) }
            }
        }
        .animation(Self.morph, value: running)
    }

    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.78)

    @ViewBuilder
    private func label(_ title: String, _ symbol: String) -> some View {
        if iconOnly {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 14)
        } else {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
    }
}

/// Focus lengths offered in context menus and the detail view.
struct FocusLengthMenu: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    static let lengths = [15, 25, 45, 50, 60, 90]

    var body: some View {
        Button("Open-ended") { store.startFocus(goal, minutes: nil) }
        Divider()
        ForEach(Self.lengths, id: \.self) { minutes in
            Button("\(minutes) minutes") { store.startFocus(goal, minutes: minutes) }
        }
    }
}

/// A clickable link with the icon of the app that opens it.
struct LinkChip: View {
    let link: GoalLink
    var tint: Color = .accentColor
    @State private var isHovered = false

    var body: some View {
        Button {
            LinkOpener.open(link)
        } label: {
            HStack(spacing: 6) {
                LinkIcon(link: link, size: 16)
                Text(link.displayTitle)
                    .lineLimit(1)
                if link.opensWithFocus {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .help("Opens when a focus session starts")
                }
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(isHovered ? 0.18 : 0.1)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(link.url.isFileURL ? link.url.path(percentEncoded: false) : link.url.absoluteString)
    }
}

/// The goal's ring, live while its timer runs.
struct GoalRing: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    var lineWidth: CGFloat = 8
    var showsIcon = true

    var body: some View {
        let engine = store.engine
        let live = engine.isRunning(goal) && store.data.session?.isRunning == true
        LiveClock(isLive: live, fallback: store.now) { now in
            ProgressRing(progress: engine.progress(for: goal, now: now), color: goal.color, lineWidth: lineWidth) {
                if showsIcon {
                    GoalGlyph(goal: goal, size: lineWidth * 2.6)
                }
            }
        }
    }
}

/// "45m / 1h 30m", live while the goal's timer runs.
struct GoalProgressText: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        let engine = store.engine
        let live = engine.isRunning(goal) && store.data.session?.isRunning == true
        LiveClock(isLive: live, fallback: store.now) { now in
            Text(goal.progressText(engine.currentAmount(for: goal, now: now), target: engine.target(for: goal)))
                .monospacedDigit()
        }
    }
}
