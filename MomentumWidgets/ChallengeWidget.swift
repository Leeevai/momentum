import AppIntents
import MomentumCore
import SwiftUI
import WidgetKit

/// A goal's challenge: the day it's on, a dot for every day, and the goal's one-tap action.
struct ChallengeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Challenge", intent: SelectGoalIntent.self, provider: GoalProvider()) { entry in
            ChallengeWidgetView(entry: entry)
                .widgetURL(entry.challengeGoal.map { DeepLink.goal($0.id).url } ?? DeepLink.today.url)
        }
        .configurationDisplayName("Challenge")
        .description("A goal's challenge: which day it is, and a dot for every day.")
        .supportedFamilies(Self.families)
    }

    #if os(iOS)
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular]
    #else
    private static let families: [WidgetFamily] = [.systemSmall, .systemMedium]
    #endif
}

extension MomentumEntry {
    /// The configured goal if it has a challenge, or else the first goal that has one.
    var challengeGoal: Goal? {
        if let goalID, let goal = engine.goal(goalID), goal.challenge != nil { return goal }
        return engine.activeGoals.first { $0.challenge != nil }
    }
}

struct ChallengeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomentumEntry

    var body: some View {
        if let goal = entry.challengeGoal, let status = entry.engine.challengeStatus(for: goal, now: entry.date) {
            switch family {
            #if os(iOS)
            case .accessoryCircular:
                ChallengeCircular(status: status)
                    .accessoryBackground()
            case .accessoryRectangular:
                ChallengeRectangular(goal: goal, status: status)
                    .accessoryBackground()
            #endif
            case .systemSmall:
                ChallengeSmall(goal: goal, status: status, entry: entry)
                    .widgetBackground(goal.tint)
            default:
                ChallengeMedium(goal: goal, status: status, entry: entry)
                    .widgetBackground(goal.tint)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "flag.2.crossed.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Start a challenge on a goal to follow it here")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .widgetBackground(.orange)
        }
    }
}

#if os(iOS)
/// The Lock Screen ring: the day number, filling as days are kept.
private struct ChallengeCircular: View {
    let status: ChallengeStatus

    var body: some View {
        Gauge(value: Double(status.kept), in: 0...Double(max(status.challenge.days, 1))) {
            Image(systemName: status.isWon ? "trophy.fill" : "flag.fill")
        } currentValueLabel: {
            if status.isWon {
                Image(systemName: "trophy.fill")
            } else {
                Text("\(status.dayNumber)")
                    .monospacedDigit()
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

private struct ChallengeRectangular: View {
    let goal: Goal
    let status: ChallengeStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(goal.name, systemImage: status.isWon ? "trophy.fill" : "flag.fill")
                .font(.headline)
                .lineLimit(1)
                .widgetAccentable()
            Text(ChallengeText.short(status))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Gauge(value: Double(status.kept), in: 0...Double(max(status.challenge.days, 1))) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

private struct ChallengeSmall: View {
    let goal: Goal
    let status: ChallengeStatus
    let entry: MomentumEntry

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(goal.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "flag.fill")
                    .font(.caption2)
                    .foregroundStyle(goal.tint)
            }
            ChallengeBadge(status: status, color: goal.color, size: 72)
            if status.isFinished {
                Text(ChallengeText.short(status))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                WidgetWideButton(goal: goal, engine: entry.engine)
            }
        }
    }
}

private struct ChallengeMedium: View {
    let goal: Goal
    let status: ChallengeStatus
    let entry: MomentumEntry

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 8) {
                ChallengeBadge(status: status, color: goal.color, size: 74)
                if !status.isFinished {
                    WidgetWideButton(goal: goal, engine: entry.engine)
                }
            }
            .frame(width: 100)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(goal.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(status.challenge.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(goal.tint)
                        .lineLimit(1)
                }
                Text(ChallengeText.short(status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ChallengeDayGrid(days: status.days, color: goal.color, dotSize: dotSize, spacing: 4)
                Spacer(minLength: 0)
            }
        }
    }

    /// Small enough that every day fits beside the badge.
    private var dotSize: CGFloat {
        switch status.days.count {
        case ...21: 15
        case ...35: 13
        case ...66: 10
        default: 8
        }
    }
}

enum ChallengeText {
    /// "Day 19 of 30 · 12 to go", "Won: 30 of 30", "27 of 30 kept".
    static func short(_ status: ChallengeStatus) -> String {
        let days = status.challenge.days
        if status.dayNumber == 0 { return "Starts soon" }
        if status.isWon { return "Won: \(days) of \(days)" }
        if status.isFinished { return "\(status.kept) of \(days) kept" }
        return "Day \(status.dayNumber) of \(days) · \(status.remaining) to go"
    }
}
