import MomentumCore
import SwiftUI

/// A goal on the Today screen: ring, progress, streak, a link and its one-tap action. Clicking it
/// opens the goal in place; with `hero`, its pane, ring and title morph into that page.
struct GoalCard: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    var hero: Namespace.ID?
    var onOpen: () -> Void = {}

    var body: some View {
        let engine = store.engine
        let now = store.now
        let streak = engine.streak(for: goal, now: now)
        let running = engine.isRunning(goal)
        let complete = engine.isComplete(goal, now: now)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                GoalRing(goal: goal, lineWidth: 5)
                    .frame(width: 46, height: 46)
                    .heroMatch("ring-\(goal.id)", in: hero)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(goal.name)
                            .font(.headline)
                            .lineLimit(1)
                            .heroMatch("title-\(goal.id)", in: hero)
                        if let rank = store.data.journalEntry(for: DayID(now))?.priorities.firstIndex(of: goal.id) {
                            Image(systemName: "\(rank + 1).circle")
                                .foregroundStyle(.secondary)
                                .help("Priority \(rank + 1) today")
                        }
                        if complete {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.success)
                                .transition(.scale.combined(with: .opacity))
                        } else if goal.streakMinimum != nil && engine.keepsStreak(goal, periodContaining: now, now: now) {
                            Label("Streak safe", systemImage: "shield.checkered")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                                .help("You've done the minimum: the streak is safe for today")
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    GoalProgressText(goal: goal)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    detailLine(engine: engine, now: now)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleOnly)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    if streak.current > 0 {
                        StreakBadge(count: streak.current, unit: streak.unit)
                    }
                    if let challenge = engine.challengeStatus(for: goal, now: now), challenge.dayNumber > 0,
                       !challenge.isFinished || challenge.isWon {
                        ChallengeChip(status: challenge)
                    }
                }
            }

            HStack(spacing: 8) {
                if running, let session = store.data.session {
                    Label {
                        SessionClockText(session: session)
                    } icon: {
                        Image(systemName: session.isRunning ? "waveform" : "pause.fill")
                    }
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                } else if let link = goal.links.first {
                    LinkChip(link: link, tint: goal.tint)
                    if goal.links.count > 1 {
                        Text("+\(goal.links.count - 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                GoalPrimaryButton(goal: goal, compact: true, prominent: false)
            }
        }
        .glassCard(tint: goal.tint, highlighted: running)
        .heroMatch("card-\(goal.id)", in: hero)
        .contentShape(RoundedRectangle(cornerRadius: GlassTokens.surfaceRadius))
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
            } else if let anchor = goal.stackAfter.flatMap(engine.goal), !anchor.isArchived {
                Label("After \(anchor.name)", systemImage: "arrow.turn.down.right")
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
                .foregroundStyle(.success)
        case .behind:
            Label("Behind · need \(goal.rateText(perDay: pace.neededPerDay ?? 0))", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.attention)
        case .noDeadline:
            Label("\(goal.format(pace.remaining)) to go", systemImage: "flag")
        }
    }
}
