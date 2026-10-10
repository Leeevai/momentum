import MomentumCore
import SwiftUI

/// A goal's challenge on its page: which day it is, a dot for every day, and how it's going.
struct ChallengeCard: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let status: ChallengeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ChallengeBadge(status: status, color: goal.color, size: 66)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.challenge.title)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(accent)
                    Text(headline)
                        .font(.title3.weight(.bold))
                        .contentTransition(.numericText())
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Menu {
                    ChallengeMenu(goal: goal)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(CircleButtonStyle(tint: .secondary, size: 30, prominent: false))
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Challenge options")
            }
            ChallengeDayGrid(days: status.days, color: goal.color)
        }
        .glassCard(tint: accent, highlighted: status.isWon)
        .animation(.snappy, value: status)
    }

    private var accent: Color { status.isWon ? .award : goal.tint }

    private var headline: String {
        let days = status.challenge.days
        if status.dayNumber == 0 { return "Starts \(startText)" }
        if status.isWon { return "Challenge complete" }
        if status.isFinished { return "\(status.kept) of \(days) days kept" }
        return "Day \(status.dayNumber) of \(days)"
    }

    private var message: String {
        let left = status.remaining
        let leftText = "\(left) \(left == 1 ? "day" : "days") to go"
        if status.dayNumber == 0 { return "Every day it's due counts, for \(status.challenge.days) days." }
        if status.isWon { return "Every day of \(status.challenge.days), kept. That's a habit now." }
        if status.isFinished {
            return "Missed \(status.missed) \(status.missed == 1 ? "day" : "days"). Start again: it gets easier."
        }
        let todayPending = status.days.contains(.today)
        if status.missed > 0 {
            return "Missed \(status.missed) so far. \(leftText): keep going, or start over."
        }
        return todayPending ? "\(leftText). Today still needs you." : "\(leftText). Today's done."
    }

    private var startText: String {
        status.challenge.start.date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// Starting, restarting or ending a goal's challenge.
struct ChallengeMenu: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        if goal.challenge != nil {
            Button("Start Over Today") { store.restartChallenge(goal) }
            Menu("Change Length") { lengths(longerThan: elapsedDays) }
            Divider()
            Button("End Challenge", role: .destructive) { store.endChallenge(goal) }
        } else {
            lengths(longerThan: 0)
        }
    }

    /// Lengths that leave days to go: shortening a challenge to its past would end it at once.
    private func lengths(longerThan elapsed: Int) -> some View {
        ForEach(Challenge.lengths.filter { $0 > elapsed && $0 != goal.challenge?.days }, id: \.self) { days in
            Button("\(days) Days") { store.startChallenge(goal, days: days, keepingStart: true) }
        }
    }

    private var elapsedDays: Int {
        store.engine.challengeStatus(for: goal, now: store.now)?.dayNumber ?? 0
    }
}
