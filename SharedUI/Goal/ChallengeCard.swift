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

    private var accent: Color { status.isWon ? .yellow : goal.tint }

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
        if let challenge = goal.challenge {
            Button("Start Over Today") { store.startChallenge(goal, days: challenge.days) }
            Menu("Change Length") { lengths }
            Divider()
            Button("End Challenge", role: .destructive) { store.endChallenge(goal) }
        } else {
            lengths
        }
    }

    private var lengths: some View {
        ForEach(Challenge.lengths, id: \.self) { days in
            Button("\(days) Days") { store.startChallenge(goal, days: days, keepingStart: true) }
        }
    }
}

/// The challenge's progress as a ring around the day number, or a trophy once it's won.
struct ChallengeBadge: View {
    let status: ChallengeStatus
    let color: GoalColor
    var size: CGFloat = 66

    var body: some View {
        ProgressRing(progress: Double(status.kept) / Double(max(status.challenge.days, 1)),
                     color: status.isWon ? .yellow : color, lineWidth: size * 0.1) {
            if status.isWon {
                Image(systemName: "trophy.fill")
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(GoalColor.yellow.linear)
                    .symbolEffect(.bounce, value: status.isWon)
            } else {
                VStack(spacing: -2) {
                    Text("\(status.dayNumber)")
                        .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(status.dayNumber)))
                    Text("of \(status.challenge.days)")
                        .font(.system(size: size * 0.14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// A dot per day: filled when kept, crossed when missed, dashed when free, ringed for today.
struct ChallengeDayGrid: View {
    let days: [ChallengeStatus.Day]
    let color: GoalColor

    var body: some View {
        let size: CGFloat = days.count > 40 ? 15 : 20
        LazyVGrid(columns: [GridItem(.adaptive(minimum: size, maximum: size + 6), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                ChallengeDot(day: day, color: color, size: size, showsMarks: days.count <= 40)
                    .help(help(for: day, index: index))
                    .accessibilityLabel(help(for: day, index: index))
            }
        }
    }

    private func help(for day: ChallengeStatus.Day, index: Int) -> String {
        let label = "Day \(index + 1)"
        switch day {
        case .kept: return "\(label): kept"
        case .missed: return "\(label): missed"
        case .free: return "\(label): a day off"
        case .today: return "\(label): today"
        case .upcoming: return "\(label): to come"
        }
    }
}

private struct ChallengeDot: View {
    let day: ChallengeStatus.Day
    let color: GoalColor
    let size: CGFloat
    let showsMarks: Bool

    var body: some View {
        ZStack {
            switch day {
            case .kept:
                Circle().fill(color.linear)
                if showsMarks {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.45, weight: .heavy))
                        .foregroundStyle(.white)
                }
            case .missed:
                Circle().strokeBorder(Color.red.opacity(0.75), lineWidth: 1.5)
                if showsMarks {
                    Image(systemName: "xmark")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.red.opacity(0.85))
                }
            case .free:
                Circle().strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2.5]))
            case .today:
                TodayDot(color: color)
            case .upcoming:
                Circle().fill(Color.secondary.opacity(0.14))
            }
        }
        .frame(width: size, height: size)
        .transition(.scale.combined(with: .opacity))
    }
}

/// Today's dot breathes until the day is kept.
private struct TodayDot: View {
    let color: GoalColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .strokeBorder(color.color, lineWidth: 2)
            .background(Circle().fill(color.color.opacity(0.15)))
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 1.18]) { dot, scale in
                dot.scaleEffect(scale)
            } animation: { _ in .easeInOut(duration: 1.1) }
    }
}

/// "Day 12/30" on a goal's Today card, or a trophy once the challenge is won.
struct ChallengeChip: View {
    let status: ChallengeStatus
    let tint: Color

    var body: some View {
        let won = status.isWon
        Label(won ? "Won" : "Day \(status.dayNumber)/\(status.challenge.days)", systemImage: won ? "trophy.fill" : "flag.fill")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(won ? .yellow : tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill((won ? Color.yellow : tint).opacity(0.14)))
            .contentTransition(.numericText(value: Double(status.dayNumber)))
            .help(won ? "\(status.challenge.title), complete" : "Day \(status.dayNumber) of a \(status.challenge.title)")
    }
}
