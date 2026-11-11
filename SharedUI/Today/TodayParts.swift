import MomentumCore
import SwiftUI

/// The day at a glance: greeting, date, one line of numbers and the goals' rings. Lays out in a
/// row when there's room and stacks on a phone.
struct TodayHeader: View {
    @Environment(GoalStore.self) private var store
    let goals: [Goal]

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting(at: store.now))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(store.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(Metrics.showsInlineTitles ? .largeTitle.weight(.semibold) : .title.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                summary
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            rings(size: Metrics.showsInlineTitles ? 84 : 64, lineWidth: Metrics.showsInlineTitles ? 8 : 6)
        }
    }

    /// Today's numbers in one quiet line, once there are goals to count.
    @ViewBuilder
    private var summary: some View {
        let engine = store.engine
        let now = store.now
        if !engine.activeGoals.isEmpty {
            let summary = engine.todaySummary(now: now)
            let focus = engine.data.goals.filter { $0.kind == .time }.reduce(0.0) { $0 + engine.amount(for: $1, on: now, now: now) }
            let parts = ["\(summary.done) of \(summary.total) done",
                         focus > 0 ? "\(Formatting.duration(focus)) focused" : nil,
                         "best streak \(engine.longestCurrentStreak(now: now))"].compactMap { $0 }
            Text(parts.joined(separator: " · "))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private func rings(size: CGFloat, lineWidth: CGFloat) -> some View {
        let engine = store.engine
        let ringGoals = Array(goals.prefix(4))
        if !ringGoals.isEmpty {
            LiveClock(isLive: store.data.session?.isRunning == true, fallback: store.now) { moment in
                RingStack(rings: ringGoals.map { ($0, engine.ringProgress(for: $0, now: moment)) }, lineWidth: lineWidth, spacing: lineWidth * 0.3)
            }
            .frame(width: size, height: size)
            .help(ringGoals.map(\.name).joined(separator: ", "))
        }
    }

    private func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<23: "Good evening"
        default: "Working late"
        }
    }
}

/// The big focus card shown while a session runs: in a row on a Mac, stacked on a phone.
struct FocusBanner: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let session: FocusSession
    @State private var note = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                ring(size: 76)
                VStack(alignment: .leading, spacing: 6) {
                    titles(clockSize: 36)
                    noteField.frame(maxWidth: 380)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 12) {
                    FocusControlCluster(goal: goal)
                    HStack(spacing: 6) { extras }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    ring(size: 60)
                    VStack(alignment: .leading, spacing: 2) { titles(clockSize: 32) }
                    Spacer(minLength: 0)
                }
                noteField
                HStack(spacing: 10) {
                    FocusControlCluster(goal: goal)
                    Spacer(minLength: 0)
                    extras
                }
            }
        }
        .glassCard(tint: goal.tint, highlighted: true)
        .onAppear { note = session.note }
    }

    private func ring(size: CGFloat) -> some View {
        LiveClock(isLive: session.isRunning, fallback: .now) { now in
            let planned = session.plannedDuration ?? 0
            ProgressRing(progress: planned > 0 ? session.elapsed(at: now) / planned : 1, color: goal.color, lineWidth: size * 0.096) {
                GoalGlyph(goal: goal, size: size * 0.28)
            }
            .opacity(session.isRunning ? 1 : 0.55)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func titles(clockSize: CGFloat) -> some View {
        Text(session.isRunning ? "Focusing on \(goal.name)" : "Paused · \(goal.name)")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentTransition(.interpolate)
        SessionClockText(session: session)
            .font(.system(size: clockSize, weight: .semibold))
            .foregroundStyle(session.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }

    private var noteField: some View {
        TextField("What are you working on?", text: $note)
            .textFieldStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .onSubmit { store.setSessionNote(note) }
            .onChange(of: note) { _, value in debounceSave(value) }
    }

    @ViewBuilder
    private var extras: some View {
        Button {
            store.isFocusModePresented = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Focus mode: full screen, nothing else in sight")
        FocusSoundMenu()
        Menu {
            if session.plannedDuration != nil {
                Button("Add 5 minutes") { store.extendFocus(by: 5) }
                Button("Add 15 minutes") { store.extendFocus(by: 15) }
                Divider()
            }
            Button("Open \(goal.name)") { store.select(goal.id) }
            ForEach(goal.links) { link in
                Button("Open \(link.displayTitle)") { LinkOpener.open(link) }
            }
            Divider()
            Button("Discard Session", role: .destructive) { store.discardFocus() }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.secondary)
        .fixedSize()
    }

    private func debounceSave(_ value: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            store.setSessionNote(value)
        }
    }
}

/// Picks the background sound for focus sessions, right from the running session.
struct FocusSoundMenu: View {
    @Environment(GoalStore.self) private var store

    var body: some View {
        let preferences = store.data.preferences
        Menu {
            Picker("Sound", selection: Binding(get: { preferences.focusSound }, set: { value in store.updatePreferences { $0.focusSound = value } })) {
                ForEach(FocusSound.allCases) { sound in
                    Label(sound.title, systemImage: sound.symbolName).tag(sound)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Volume", selection: Binding(get: { (preferences.focusSoundVolume * 4).rounded() / 4 }, set: { value in store.updatePreferences { $0.focusSoundVolume = value } })) {
                Text("Quiet").tag(0.25)
                Text("Medium").tag(0.5)
                Text("Loud").tag(0.75)
                Text("Full").tag(1.0)
            }
        } label: {
            Image(systemName: preferences.focusSound == .off ? "speaker.slash" : "speaker.wave.2.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.secondary)
        .fixedSize()
        .help("Focus sound: \(preferences.focusSound.title)")
    }
}

/// Shows which goals a macOS Focus is limiting Today to, with a way past it.
struct FocusFilterBanner: View {
    let filter: FocusFilter
    var onShowAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon")
                .foregroundStyle(.secondary)
            Text("Focus filter: showing \(filter.categories.sorted().formatted(.list(type: .and))) goals.")
                .font(.callout)
            Spacer()
            Button("Show all", action: onShowAll)
                .secondaryActionStyle(.accent, compact: true)
        }
        .glassCard(padding: 12)
    }
}

/// First-run screen: a few one-click templates.
struct WelcomeView: View {
    #if os(macOS)
    static let whereWidgetsLive = "on your desktop"
    #else
    static let whereWidgetsLive = "on your Home Screen"
    #endif

    @Environment(GoalStore.self) private var store

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 16) {
                MomentumMark(size: 112)
                    .padding(.bottom, 6)
                Text("Show up for what matters")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Momentum turns big intentions into small daily wins. Track focus time, habits, books, savings, or a project's milestones, and watch your streaks grow \(Self.whereWidgetsLive).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
                Button {
                    store.sheet = .newGoal
                } label: {
                    Label("Create your first goal", systemImage: "plus")
                }
                .primaryActionStyle(.accent)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            Text("Or start from a template")
                .font(.headline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                ForEach(GoalTemplate.all.prefix(6)) { template in
                    Button {
                        let goal = template.makeGoal()
                        store.perform("Add Goal") { $0.upsert(goal) }
                    } label: {
                        TemplateTile(template: template)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
