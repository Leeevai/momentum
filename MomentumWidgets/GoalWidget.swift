import AppIntents
import MomentumCore
import SwiftUI
import WidgetKit

/// One goal in depth. Adapts to the goal: heatmap, current book, or next milestones.
struct GoalWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Goal", intent: SelectGoalIntent.self, provider: GoalProvider()) { entry in
            GoalWidgetView(entry: entry)
                .widgetBackground(entry.goal?.tint ?? .blue)
                .widgetURL(entry.goal.map { DeepLink.goal($0.id).url } ?? DeepLink.today.url)
        }
        .configurationDisplayName("Goal")
        .description("One goal's ring, streak and history: heatmap, reading progress, or milestones.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SelectGoalIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Goal"
    static let description = IntentDescription("Pick the goal this widget shows.")

    @Parameter(title: "Goal")
    var goal: GoalEntity?
}

struct GoalProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MomentumEntry {
        MomentumEntry(date: .now, engine: ProgressEngine(data: .demo()))
    }

    func snapshot(for configuration: SelectGoalIntent, in context: Context) async -> MomentumEntry {
        WidgetTimeline.entry(preview: context.isPreview, goalID: configuration.goal?.id)
    }

    func timeline(for configuration: SelectGoalIntent, in context: Context) async -> Timeline<MomentumEntry> {
        WidgetTimeline.timeline(goalID: configuration.goal?.id)
    }
}

struct GoalWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomentumEntry

    var body: some View {
        if let goal = entry.goal {
            switch family {
            case .systemSmall: GoalSmall(goal: goal, entry: entry)
            case .systemLarge: GoalLarge(goal: goal, entry: entry)
            default: GoalMedium(goal: goal, entry: entry)
            }
        } else {
            WidgetEmptyView()
        }
    }
}

private struct GoalSmall: View {
    let goal: Goal
    let entry: MomentumEntry

    var body: some View {
        let streak = entry.engine.streak(for: goal, now: entry.date)
        VStack(spacing: 6) {
            HStack {
                Text(goal.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                StreakBadge(count: streak.current, unit: streak.unit)
            }
            WidgetGoalRing(goal: goal, engine: entry.engine, now: entry.date)
            WidgetWideButton(goal: goal, engine: entry.engine)
        }
    }
}

private struct GoalMedium: View {
    let goal: Goal
    let entry: MomentumEntry

    var body: some View {
        let engine = entry.engine
        let streak = engine.streak(for: goal, now: entry.date)
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                WidgetGoalRing(goal: goal, engine: engine, now: entry.date)
                WidgetWideButton(goal: goal, engine: engine)
            }
            .frame(width: 108)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(goal.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    StreakBadge(count: streak.current, unit: streak.unit)
                }
                Text(subtitle(engine: engine, streak: streak))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                GoalDetailPanel(goal: goal, entry: entry, compact: true)
            }
        }
    }

    private func subtitle(engine: ProgressEngine, streak: ProgressEngine.Streak) -> String {
        let progress = goal.progressText(engine.currentAmount(for: goal, now: entry.date), target: engine.target(for: goal))
        return "\(progress) · best \(streak.best)"
    }
}

private struct GoalLarge: View {
    let goal: Goal
    let entry: MomentumEntry

    var body: some View {
        let engine = entry.engine
        let streak = engine.streak(for: goal, now: entry.date)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(goal.icon)
                Text(goal.name).font(.headline).lineLimit(1)
                Spacer()
                Text(goal.targetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 16) {
                WidgetGoalRing(goal: goal, engine: engine, now: entry.date, lineWidth: 10)
                    .frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 7) {
                    stat("Current streak", "\(streak.current) \(Formatting.unit("\(streak.unit)s", for: Double(streak.current)))")
                    stat("Best streak", "\(streak.best) \(Formatting.unit("\(streak.unit)s", for: Double(streak.best)))")
                    if let rate = engine.completionRate(for: goal, now: entry.date) {
                        stat("Hit rate", Formatting.percent(rate))
                    } else {
                        stat(goal.effectivePeriod.currentLabel, goal.progressText(engine.currentAmount(for: goal, now: entry.date), target: engine.target(for: goal)))
                    }
                }
                Spacer(minLength: 0)
            }
            WidgetWideButton(goal: goal, engine: engine)
            GoalDetailPanel(goal: goal, entry: entry, compact: false)
            if !goal.links.isEmpty {
                HStack(spacing: 6) {
                    ForEach(goal.links.prefix(3)) { link in
                        Link(destination: DeepLink.openLink(goal: goal.id, link: link.id).url) {
                            Label(link.displayTitle, systemImage: link.isFile ? "doc" : "link")
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(goal.tint.opacity(0.14)))
                        }
                    }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.subheadline, design: .rounded, weight: .semibold)).lineLimit(1)
        }
    }
}

/// What a goal shows beyond its ring: the current book, upcoming milestones, or a heatmap.
private struct GoalDetailPanel: View {
    let goal: Goal
    let entry: MomentumEntry
    let compact: Bool

    var body: some View {
        switch goal.kind {
        case .books:
            if let book = goal.currentBook {
                HStack(alignment: .top, spacing: 8) {
                    if let cover = CoverCache.image(for: book) {
                        Image(nsImage: cover)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: compact ? 30 : 40, height: compact ? 44 : 60)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 1.5, x: 1, y: 1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Label(book.title, systemImage: "book")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if !book.author.isEmpty && !compact {
                            Text(book.author).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let fraction = book.fraction {
                            ProgressBar(progress: fraction, color: goal.color, height: 5)
                            Text("p. \(book.currentPage) of \(book.totalPages ?? 0)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Text("No book in progress. Tap to pick one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if !compact {
                Heatmap(engine: entry.engine, goal: goal, now: entry.date)
            }
        case .milestones:
            let upcoming = goal.milestones.filter { !$0.isDone }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(upcoming.prefix(compact ? 3 : 6)) { milestone in
                    Label(milestone.title, systemImage: "circle")
                        .font(.caption)
                        .lineLimit(1)
                }
                if upcoming.isEmpty {
                    Label("All milestones done", systemImage: "flag.checkered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        case .time, .count, .amount:
            Heatmap(engine: entry.engine, goal: goal, now: entry.date, spacing: compact ? 2.5 : 3)
        }
    }
}
