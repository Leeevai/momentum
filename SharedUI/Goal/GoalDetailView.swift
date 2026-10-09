import MomentumCore
import SwiftUI

struct GoalDetailView: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        ScrollView {
            GoalDetailContent(goal: goal)
                .padding(Metrics.screenPadding)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(LivingBackdrop(primary: goal.tint, secondary: goal.color.highlight))
        .navigationTitle(goal.name)
        #if os(macOS)
        .navigationSubtitle(goal.targetDescription)
        #endif
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

/// Everything on a goal's page. Shown as a page from the sidebar, or inside a Today card that
/// morphs open, in which case `hero` ties its icon, title and ring to the card's.
struct GoalDetailContent: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    var hero: Namespace.ID?

    var body: some View {
        let engine = store.engine
        let now = store.now
        VStack(alignment: .leading, spacing: 22) {
            GoalHeader(goal: goal, hero: hero)
            HeroPanel(goal: goal, hero: hero)
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
    }
}

private struct GoalHeader: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    var hero: Namespace.ID?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            GoalIcon(goal: goal, size: Metrics.showsInlineTitles ? 64 : 54)
                .heroMatch("icon-\(goal.id)", in: hero)
            VStack(alignment: .leading, spacing: 6) {
                Text(goal.name)
                    .font(.system(size: Metrics.showsInlineTitles ? 30 : 26, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .heroMatch("title-\(goal.id)", in: hero)
                FlowLayout(spacing: 8) { meta }
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

    /// Category, target, schedule and reminder, wrapping onto a second line on a phone.
    @ViewBuilder
    private var meta: some View {
        if !goal.category.isEmpty {
            CategoryPill(text: goal.category, tint: goal.tint)
        }
        Label(goal.targetDescription, systemImage: goal.kind.symbolName)
        Label(goal.scheduleDescription(), systemImage: "calendar")
        if let reminder = goal.reminder, reminder.isEnabled {
            Label(reminderTime(reminder), systemImage: "bell")
        }
    }

    private var breakText: String {
        guard let active = goal.activeBreak(at: store.now) else { return "On a break" }
        if active.end == .distantFuture { return "On a break until you resume. Your streak is safe." }
        return "On a break until \(active.end.addingTimeInterval(-1).formatted(.dateTime.weekday(.wide).month().day())). Your streak is safe."
    }

    private func reminderTime(_ reminder: ReminderSchedule) -> String {
        let date = Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: .now) ?? .now
        let time = date.formatted(date: .omitted, time: .shortened)
        guard let every = reminder.repeatMinutes else { return time }
        return "\(time), every \(every >= 60 ? "\(every / 60)h" : "\(every)m")"
    }
}

private struct HeroPanel: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    var hero: Namespace.ID?

    var body: some View {
        let running = store.engine.isRunning(goal)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 28) {
                ring
                TrackingControls(goal: goal)
                    .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .center, spacing: 20) {
                ring
                TrackingControls(goal: goal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .glassCard(tint: goal.tint, cornerRadius: 24, padding: 22, highlighted: running)
    }

    private var ring: some View {
        let engine = store.engine
        let running = engine.isRunning(goal)
        return LiveClock(isLive: running && store.data.session?.isRunning == true, fallback: store.now) { now in
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
        .heroMatch("ring-\(goal.id)", in: hero)
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

    private func rateText(_ perDay: Double) -> String {
        goal.rateText(perDay: perDay)
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
                if goal.kind == .time, let sessions = engine.sessionStats(for: goal) {
                    StatTile(title: "Sessions", value: "\(sessions.count)", systemImage: "timer", tint: goal.tint,
                             caption: "avg \(Formatting.duration(sessions.average)) · longest \(Formatting.duration(sessions.longest))")
                }
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
