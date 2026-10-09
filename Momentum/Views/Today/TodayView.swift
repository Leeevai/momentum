import MomentumCore
import SwiftUI

struct TodayView: View {
    @Environment(GoalStore.self) private var store
    /// A per-Mac convenience, so it lives in user defaults rather than the shared data.
    @AppStorage("dismissedWidgetTip") private var dismissedWidgetTip = false

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 16)]

    var body: some View {
        let engine = store.engine
        let now = store.now
        let today = store.filteredForFocus(engine.todayGoals(now: now))
        let upNext = today.filter { !engine.isComplete($0, now: now) }
        let done = today.filter { engine.isComplete($0, now: now) }
        let resting = store.filteredForFocus(engine.activeGoals.filter { $0.isOnBreak(at: now) && !engine.isRunning($0) })

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                TodayHeader(goals: today)

                if let filter = store.activeFocusFilter {
                    FocusFilterBanner(filter: filter) {
                        withAnimation { store.ignoredFocusFilter = filter }
                    }
                }

                if let session = store.data.session, let goal = store.goal(session.goalID) {
                    FocusBanner(goal: goal, session: session)
                        // A new session gets a fresh banner, so the note field never carries over.
                        .id(session.startedAt)
                        .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
                }

                if engine.activeGoals.isEmpty {
                    WelcomeView()
                } else {
                    if !dismissedWidgetTip {
                        WidgetTip { withAnimation { dismissedWidgetTip = true } }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if !upNext.isEmpty {
                        section("Up next", systemImage: "arrow.forward.circle", goals: upNext)
                    } else if !today.isEmpty {
                        allDoneBanner
                    }
                    if !done.isEmpty {
                        section("Done", systemImage: "checkmark.circle", goals: done)
                    }
                    if today.isEmpty && resting.isEmpty {
                        Text("Nothing is due today. Enjoy the day off, or get ahead from the sidebar.")
                            .foregroundStyle(.secondary)
                    }
                    if !resting.isEmpty {
                        section("On a break", systemImage: "pause.circle", goals: resting)
                            .opacity(0.75)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: done.map(\.id))
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.data.session?.goalID)
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground(primary: .accentColor, secondary: .purple))
        .navigationTitle("Today")
    }

    private func section(_ title: String, systemImage: String, goals: [Goal]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(goals) { goal in
                    GoalCard(goal: goal)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
    }

    private var allDoneBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green.gradient)
                .symbolEffect(.bounce, value: store.engine.todaySummary(now: store.now).done)
            VStack(alignment: .leading, spacing: 2) {
                Text("Everything is done for today")
                    .font(.title3.weight(.semibold))
                Text("That's how momentum is built. See you tomorrow.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .green, highlighted: false)
    }
}

/// Shows which goals a macOS Focus is limiting Today to, with a way past it.
private struct FocusFilterBanner: View {
    let filter: FocusFilter
    var onShowAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.circle.fill")
                .font(.title2)
                .foregroundStyle(.indigo)
            Text("Focus filter: showing \(filter.categories.sorted().formatted(.list(type: .and))) goals.")
                .font(.callout)
            Spacer()
            Button("Show all", action: onShowAll)
                .buttonStyle(PillButtonStyle(tint: .indigo, prominent: false, compact: true))
        }
        .glassCard(tint: .indigo, padding: 12)
    }
}

/// Points first-time users at the desktop widgets.
private struct WidgetTip: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 28))
                .foregroundStyle(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 3) {
                Text("Put Momentum on your desktop")
                    .font(.headline)
                Text("Right-click the desktop, choose Edit Widgets, and search for Momentum. Widgets start timers, check in and log pages without opening the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Got it", action: onDismiss)
                .buttonStyle(PillButtonStyle(tint: .orange, prominent: false, compact: true))
        }
        .glassCard(tint: .orange)
    }
}

private struct TodayHeader: View {
    @Environment(GoalStore.self) private var store
    let goals: [Goal]

    var body: some View {
        let engine = store.engine
        let now = store.now
        let summary = engine.todaySummary(now: now)
        let fraction = summary.total == 0 ? 0 : Double(summary.done) / Double(summary.total)
        let focus = engine.data.goals.filter { $0.kind == .time }.reduce(0.0) { $0 + engine.amount(for: $1, on: now, now: now) }
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting(at: now))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                HStack(spacing: 10) {
                    HeaderChip(systemImage: "checkmark.circle.fill", text: "\(summary.done) of \(summary.total) done", tint: .green)
                    HeaderChip(systemImage: "flame.fill", text: "Best streak \(engine.longestCurrentStreak(now: now))", tint: .orange)
                    if focus > 0 {
                        HeaderChip(systemImage: "timer", text: "\(Formatting.duration(focus)) focused", tint: .indigo)
                    }
                }
            }
            Spacer(minLength: 16)
            if summary.total > 0 {
                ProgressRing(progress: fraction, color: .blue, lineWidth: 12) {
                    VStack(spacing: 0) {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .contentTransition(.numericText(value: fraction))
                        Text("today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 112, height: 112)
            }
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

private struct HeaderChip: View {
    let systemImage: String
    let text: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.12)))
            .contentTransition(.numericText())
    }
}

/// The big focus card shown while a session runs.
struct FocusBanner: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let session: FocusSession
    @State private var note = ""

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            LiveClock(isLive: session.isRunning, fallback: .now) { now in
                let planned = session.plannedDuration ?? 0
                ProgressRing(progress: planned > 0 ? session.elapsed(at: now) / planned : 1, color: goal.color, lineWidth: 10) {
                    Text(goal.icon).font(.system(size: 34))
                }
                .opacity(session.isRunning ? 1 : 0.55)
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(session.isRunning ? "Focusing on" : "Paused")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(goal.tint)
                        .textCase(.uppercase)
                    if session.isRunning {
                        Image(systemName: "waveform")
                            .foregroundStyle(goal.tint)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                }
                Text(goal.name)
                    .font(.title2.weight(.bold))
                SessionClockText(session: session)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(session.isRunning ? AnyShapeStyle(goal.color.linear) : AnyShapeStyle(.secondary))
                TextField("What are you working on?", text: $note)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    .frame(maxWidth: 380)
                    .onSubmit { store.setSessionNote(note) }
                    .onChange(of: note) { _, value in debounceSave(value) }
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button {
                    store.togglePause()
                } label: {
                    Label(session.isRunning ? "Pause" : "Resume", systemImage: session.isRunning ? "pause.fill" : "play.fill")
                        .frame(minWidth: 96)
                }
                .buttonStyle(PillButtonStyle(tint: goal.tint, prominent: false))
                Button {
                    store.setSessionNote(note)
                    store.stopFocus()
                } label: {
                    Label("Stop & save", systemImage: "stop.fill")
                        .frame(minWidth: 96)
                }
                .buttonStyle(PillButtonStyle(tint: goal.tint))
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
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .glassCard(tint: goal.tint, cornerRadius: 24, padding: 22, highlighted: true)
        .onAppear { note = session.note }
    }

    @State private var saveTask: Task<Void, Never>?

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
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Focus sound: \(preferences.focusSound.title)")
    }
}

/// First-run screen: a few one-click templates.
private struct WelcomeView: View {
    @Environment(GoalStore.self) private var store

    var body: some View {
        VStack(spacing: 22) {
            EmptyStateView(
                systemImage: "sparkles",
                title: "Show up for what matters",
                message: "Momentum turns big intentions into small daily wins. Track focus time, habits, books, savings, or a project's milestones, and watch your streaks grow on your desktop."
            ) {
                Button {
                    store.sheet = .newGoal
                } label: {
                    Label("Create your first goal", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle(tint: .accentColor))
                .controlSize(.large)
            }
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
