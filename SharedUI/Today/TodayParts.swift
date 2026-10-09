import MomentumCore
import SwiftUI

/// The day at a glance: greeting, date, a few numbers and the goals' rings. Lays out in a row
/// when there's room and stacks on a phone.
struct TodayHeader: View {
    @Environment(GoalStore.self) private var store
    let goals: [Goal]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    titles(dateSize: 36)
                    HStack(spacing: 10) { chips }
                }
                Spacer(minLength: 16)
                rings(size: 128, lineWidth: 13)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) { titles(dateSize: 30) }
                    Spacer(minLength: 8)
                    rings(size: 86, lineWidth: 9)
                }
                FlowLayout(spacing: 8) { chips }
            }
        }
    }

    @ViewBuilder
    private func titles(dateSize: CGFloat) -> some View {
        Text(greeting(at: store.now))
            .font(.title3.weight(.medium))
            .foregroundStyle(.secondary)
        Text(store.now, format: .dateTime.weekday(.wide).month(.wide).day())
            .font(.system(size: dateSize, weight: .bold, design: .rounded))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Today's numbers, once there are goals to count.
    @ViewBuilder
    private var chips: some View {
        let engine = store.engine
        let now = store.now
        if !engine.activeGoals.isEmpty {
            let summary = engine.todaySummary(now: now)
            let focus = engine.data.goals.filter { $0.kind == .time }.reduce(0.0) { $0 + engine.amount(for: $1, on: now, now: now) }
            HeaderChip(systemImage: "checkmark.circle.fill", text: "\(summary.done) of \(summary.total) done", tint: .green)
            HeaderChip(systemImage: "flame.fill", text: "Best streak \(engine.longestCurrentStreak(now: now))", tint: .orange)
            if focus > 0 {
                HeaderChip(systemImage: "timer", text: "\(Formatting.duration(focus)) focused", tint: .indigo)
            }
        }
    }


    @ViewBuilder
    private func rings(size: CGFloat, lineWidth: CGFloat) -> some View {
        let engine = store.engine
        let ringGoals = Array(goals.prefix(4))
        if !ringGoals.isEmpty {
            LiveClock(isLive: store.data.session?.isRunning == true, fallback: store.now) { moment in
                RingStack(rings: ringGoals.map { ($0, engine.progress(for: $0, now: moment)) }, lineWidth: lineWidth, spacing: lineWidth * 0.23)
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

struct HeaderChip: View {
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
            .fixedSize()
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
            HStack(alignment: .center, spacing: 22) {
                ring(size: 104)
                VStack(alignment: .leading, spacing: 8) {
                    titles(clockSize: 46)
                    noteField.frame(maxWidth: 380)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 12) {
                    FocusControlCluster(goal: goal)
                    HStack(spacing: 6) { extras }
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    ring(size: 78)
                    VStack(alignment: .leading, spacing: 4) { titles(clockSize: 38) }
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
        .glassCard(tint: goal.tint, cornerRadius: 26, padding: 20, highlighted: true)
        .onAppear { note = session.note }
    }

    private func ring(size: CGFloat) -> some View {
        LiveClock(isLive: session.isRunning, fallback: .now) { now in
            let planned = session.plannedDuration ?? 0
            ProgressRing(progress: planned > 0 ? session.elapsed(at: now) / planned : 1, color: goal.color, lineWidth: size * 0.096) {
                GoalGlyph(goal: goal, size: size * 0.31)
                    .symbolEffect(.pulse, options: .repeating, isActive: session.isRunning)
            }
            .opacity(session.isRunning ? 1 : 0.55)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func titles(clockSize: CGFloat) -> some View {
        HStack(spacing: 8) {
            Text(session.isRunning ? "Focusing on" : "Paused")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(goal.tint)
                .textCase(.uppercase)
                .contentTransition(.interpolate)
            if session.isRunning {
                Image(systemName: "waveform")
                    .foregroundStyle(goal.tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
        }
        Text(goal.name)
            .font(.title2.weight(.bold))
            .lineLimit(1)
        SessionClockText(session: session)
            .font(.system(size: clockSize, weight: .bold, design: .rounded))
            .foregroundStyle(session.isRunning ? AnyShapeStyle(goal.color.linear) : AnyShapeStyle(.secondary))
    }

    private var noteField: some View {
        TextField("What are you working on?", text: $note)
            .textFieldStyle(.plain)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
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
        .foregroundStyle(goal.tint)
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
            Image(systemName: "moon.circle.fill")
                .font(.title2)
                .foregroundStyle(.indigo)
            Text("Focus filter: showing \(filter.categories.sorted().formatted(.list(type: .and))) goals.")
                .font(.callout)
            Spacer()
            Button("Show all", action: onShowAll)
                .secondaryActionStyle(.indigo, compact: true)
        }
        .glassCard(tint: .indigo, padding: 12)
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
                    .font(.system(.title, design: .rounded, weight: .bold))
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
