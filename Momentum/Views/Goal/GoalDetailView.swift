import MomentumCore
import SwiftUI

struct GoalDetailView: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        let engine = store.engine
        let now = store.now
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GoalHeader(goal: goal)
                HeroPanel(goal: goal)
                if let pace = engine.pace(for: goal, now: now), pace.status != .done {
                    PaceCard(goal: goal, pace: pace)
                }
                StatsRow(goal: goal)
                if goal.kind == .books {
                    BooksSection(goal: goal)
                }
                if goal.kind == .milestones || !goal.milestones.isEmpty {
                    MilestonesSection(goal: goal)
                }
                ActivityChartCard(goal: goal)
                HeatmapCard(goal: goal)
                LinksSection(goal: goal)
                if goal.kind != .milestones && goal.milestones.isEmpty {
                    MilestonesSection(goal: goal, collapsedWhenEmpty: true)
                }
                HistorySection(goal: goal)
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(primary: goal.tint, secondary: goal.color.highlight))
        .navigationTitle(goal.name)
        .navigationSubtitle(goal.targetDescription)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.sheet = .editGoal(goal)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                .help("Edit goal (⌘E)")
                .keyboardShortcut("e", modifiers: .command)
                Menu {
                    GoalContextMenu(goal: goal)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("More actions")
            }
        }
    }
}

private struct GoalHeader: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            GoalIcon(goal: goal, size: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    if !goal.category.isEmpty {
                        CategoryPill(text: goal.category, tint: goal.tint)
                    }
                    Label(goal.targetDescription, systemImage: goal.kind.symbolName)
                    Text("·").foregroundStyle(.tertiary)
                    Text(goal.scheduleDescription())
                    if let reminder = goal.reminder, reminder.isEnabled {
                        Text("·").foregroundStyle(.tertiary)
                        Label(reminderTime(reminder), systemImage: "bell")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if goal.isOnBreak(at: store.now) {
                    Label(breakText, systemImage: "pause.circle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                }
                if !goal.details.isEmpty {
                    Text(goal.details)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Capsule().fill(goal.tint.opacity(0.6)).frame(width: 3)
                        }
                        .padding(.top, 4)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var breakText: String {
        guard let active = goal.activeBreak(at: store.now) else { return "On a break" }
        if active.end == .distantFuture { return "On a break until you resume. Your streak is safe." }
        return "On a break until \(active.end.addingTimeInterval(-1).formatted(.dateTime.weekday(.wide).month().day())). Your streak is safe."
    }

    private func reminderTime(_ reminder: ReminderSchedule) -> String {
        let date = Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct HeroPanel: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        let engine = store.engine
        let running = engine.isRunning(goal)
        HStack(alignment: .center, spacing: 28) {
            LiveClock(isLive: running && store.data.session?.isRunning == true, fallback: store.now) { now in
                let amount = engine.currentAmount(for: goal, now: now)
                ProgressRing(progress: engine.progress(for: goal, now: now), color: goal.color, lineWidth: 14) {
                    VStack(spacing: 2) {
                        Text(goal.formatShort(amount))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: amount))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("of \(goal.formatShort(engine.target(for: goal)))\(goal.kind == .time ? "" : " \(goal.displayUnit)")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(goal.effectivePeriod.currentLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(goal.tint)
                            .textCase(.uppercase)
                    }
                    .padding(18)
                }
            }
            .frame(width: 168, height: 168)

            TrackingControls(goal: goal)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard(tint: goal.tint, cornerRadius: 24, padding: 22, highlighted: running)
    }
}

private struct PaceCard: View {
    let goal: Goal
    let pace: ProgressEngine.Pace

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(tint.gradient)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard(tint: tint)
    }

    private var tint: Color {
        switch pace.status {
        case .onTrack, .done: .green
        case .behind: .orange
        case .noDeadline: goal.tint
        }
    }

    private var icon: String {
        switch pace.status {
        case .onTrack, .done: "chart.line.uptrend.xyaxis"
        case .behind: "exclamationmark.triangle.fill"
        case .noDeadline: "flag.checkered"
        }
    }

    private var title: String {
        switch pace.status {
        case .done: "Target reached"
        case .onTrack: "On track"
        case .behind: "Falling behind"
        case .noDeadline: "\(goal.format(pace.remaining)) to go"
        }
    }

    private var message: String {
        let rate = rateText(pace.recentPerDay)
        let finish = pace.projectedFinish.map { "At your recent pace (\(rate)) you'll finish around \(Self.dayText($0))." }
            ?? "Log some progress to see a projected finish date."
        guard let deadline = pace.deadline, let needed = pace.neededPerDay else { return finish }
        let due = Self.dayText(deadline.addingTimeInterval(-1))
        return "\(goal.format(pace.remaining)) left by \(due): \(rateText(needed)) gets you there. \(finish)"
    }

    /// "17 November", with the year added when it is not this year.
    static func dayText(_ date: Date) -> String {
        Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            ? date.formatted(.dateTime.month(.wide).day())
            : date.formatted(.dateTime.month(.wide).day().year())
    }

    /// Books move slowly, so their rate reads per month; everything else per day.
    private func rateText(_ perDay: Double) -> String {
        goal.kind == .books ? "\(Formatting.number(perDay * 30)) books a month" : "\(goal.format(perDay)) a day"
    }
}

private struct StatsRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        let engine = store.engine
        let now = store.now
        let streak = engine.streak(for: goal, now: now)
        let unit = streak.unit
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)], spacing: 14) {
            StatTile(title: "Current streak", value: "\(streak.current) \(Formatting.unit("\(unit)s", for: Double(streak.current)))", systemImage: "flame.fill", tint: .orange,
                     caption: goal.kind == .books || goal.kind == .milestones ? "Days with progress" : nil)
            StatTile(title: "Best streak", value: "\(streak.best) \(Formatting.unit("\(unit)s", for: Double(streak.best)))", systemImage: "trophy.fill", tint: .yellow)
            if goal.kind == .books {
                let year = engine.interval(of: .yearly, containing: now)
                StatTile(title: "Books this year", value: "\(engine.booksFinished(for: goal, in: year))", systemImage: "books.vertical.fill", tint: goal.tint)
                StatTile(title: "Pages read", value: Formatting.number(engine.lifetimeAmount(for: goal, now: now)), systemImage: "book.pages.fill", tint: .brown,
                         caption: "\(Formatting.number(engine.amount(for: goal, in: engine.interval(of: .monthly, containing: now), now: now))) this month")
            } else if goal.kind == .milestones {
                let done = goal.milestones.filter(\.isDone).count
                StatTile(title: "Completed", value: "\(done) of \(goal.milestones.count)", systemImage: "flag.checkered", tint: goal.tint)
                StatTile(title: "Remaining", value: "\(goal.milestones.count - done)", systemImage: "list.bullet", tint: .secondary)
            } else {
                StatTile(title: "Hit rate", value: Formatting.percent(engine.completionRate(for: goal, now: now)), systemImage: "target", tint: goal.tint,
                         caption: rateCaption)
                StatTile(title: "All time", value: goal.format(engine.lifetimeAmount(for: goal, now: now)), systemImage: "sum", tint: .secondary,
                         caption: "Since \(engine.firstDay(of: goal).formatted(.dateTime.month(.abbreviated).day().year()))")
            }
        }
    }

    private var rateCaption: String {
        switch goal.effectivePeriod {
        case .daily: "Last 30 days"
        case .weekly: "Last 12 weeks"
        case .monthly: "Last 12 months"
        case .yearly: "Last 5 years"
        case .total: "Overall"
        }
    }
}
