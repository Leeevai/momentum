import MomentumCore
import SwiftUI

// Challenge views shared by the apps and the widgets.

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
    /// The dots' size; by default 20 points, or 15 for a long challenge.
    var dotSize: CGFloat?
    var spacing: CGFloat = 6

    var body: some View {
        let size = dotSize ?? (days.count > 40 ? 15 : 20)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: size, maximum: size + spacing), spacing: spacing)], alignment: .leading, spacing: spacing) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                ChallengeDot(day: day, color: color, size: size, showsMarks: size >= 14 && days.count <= 40)
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
