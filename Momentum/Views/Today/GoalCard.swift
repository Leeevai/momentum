import MomentumCore
import SwiftUI

/// A goal on the Today screen: ring, progress, streak, links and its one-tap action. Clicking it
/// opens the goal in place; with `hero`, its glass, ring and title morph into that page.
struct GoalCard: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    var hero: Namespace.ID?
    var onOpen: () -> Void = {}
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let engine = store.engine
        let now = store.now
        let streak = engine.streak(for: goal, now: now)
        let running = engine.isRunning(goal)
        let complete = engine.isComplete(goal, now: now)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                GoalRing(goal: goal, lineWidth: 7)
                    .frame(width: 62, height: 62)
                    .heroMatch("ring-\(goal.id)", in: hero)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(goal.name)
                            .font(.headline)
                            .lineLimit(1)
                            .heroMatch("title-\(goal.id)", in: hero)
                        if complete {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        } else if goal.streakMinimum != nil && engine.keepsStreak(goal, periodContaining: now, now: now) {
                            Label("Streak safe", systemImage: "shield.checkered")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.orange)
                                .help("You've done the minimum: the streak is safe for today")
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    GoalProgressText(goal: goal)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    detailLine(engine: engine, now: now)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    StreakBadge(count: streak.current, unit: streak.unit)
                    Text(goal.effectivePeriod.currentLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                if running, let session = store.data.session {
                    Label {
                        SessionClockText(session: session)
                    } icon: {
                        Image(systemName: session.isRunning ? "waveform" : "pause.fill")
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: session.isRunning)
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(goal.tint)
                } else if let link = goal.links.first {
                    LinkChip(link: link, tint: goal.tint)
                    if goal.links.count > 1 {
                        Text("+\(goal.links.count - 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                GoalPrimaryButton(goal: goal, compact: true)
            }
        }
        .glassCard(tint: goal.tint, highlighted: running)
        .heroMatch("card-\(goal.id)", in: hero)
        .scaleEffect(isHovered && !reduceMotion ? 1.012 : 1)
        .shadow(color: goal.tint.opacity(isHovered ? 0.18 : 0), radius: 16, y: 6)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onOpen)
        .contextMenu { GoalContextMenu(goal: goal) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(goal.name)
    }

    /// A second line that depends on the goal: the current book, the next milestone, or pace.
    @ViewBuilder
    private func detailLine(engine: ProgressEngine, now: Date) -> some View {
        switch goal.kind {
        case .books:
            if let book = goal.currentBook {
                Label("\(book.title)\(book.totalPages.map { " · p. \(book.currentPage)/\($0)" } ?? "")", systemImage: "book")
            } else {
                Label("No book in progress", systemImage: "book.closed")
            }
        case .milestones:
            if let next = goal.milestones.first(where: { !$0.isDone }) {
                Label("Next: \(next.title)", systemImage: "flag")
            } else {
                Label("All milestones complete", systemImage: "flag.checkered")
            }
        case .time, .count, .amount:
            if let pace = engine.pace(for: goal, now: now), pace.status != .done {
                PaceLabel(goal: goal, pace: pace)
            } else {
                Label(goal.scheduleDescription(), systemImage: "calendar")
            }
        }
    }
}

struct PaceLabel: View {
    let goal: Goal
    let pace: ProgressEngine.Pace

    var body: some View {
        switch pace.status {
        case .done:
            Label("Target reached", systemImage: "checkmark.seal")
        case .onTrack:
            Label("On track\(pace.neededPerDay.map { " · \(goal.rateText(perDay: $0))" } ?? "")", systemImage: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.green)
        case .behind:
            Label("Behind · need \(goal.rateText(perDay: pace.neededPerDay ?? 0))", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .noDeadline:
            Label("\(goal.format(pace.remaining)) to go", systemImage: "flag")
        }
    }
}
