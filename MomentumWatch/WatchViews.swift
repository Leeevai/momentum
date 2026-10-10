import MomentumCore
import SwiftUI

/// Today on the watch: the timer if one is running, then each goal with its ring.
struct WatchRoot: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [UUID] = []

    var body: some View {
        let snapshot = store.snapshot
        let palette = snapshot.palette ?? .standard
        NavigationStack(path: $path) {
            List {
                if let session = snapshot.session, let item = snapshot.item(session.goalID) {
                    Section {
                        NavigationLink(value: item.id) {
                            SessionRow(session: session, item: item)
                        }
                        .listItemTint(palette.color(item.color).opacity(0.35))
                    }
                } else if let rest = snapshot.rest, let item = snapshot.item(rest.goalID) {
                    Section {
                        RestRow(rest: rest, item: item)
                    }
                }
                Section {
                    ForEach(snapshot.items) { item in
                        NavigationLink(value: item.id) {
                            GoalRow(item: item)
                        }
                    }
                } header: {
                    if snapshot.total > 0 {
                        Text("\(snapshot.done) of \(snapshot.total) done")
                    }
                } footer: {
                    if snapshot.items.isEmpty {
                        Text(snapshot.generatedAt == .distantPast
                             ? "Open Momentum on your iPhone to bring your goals here."
                             : "Nothing due today. Enjoy it.")
                    } else if store.queuedActions > 0 {
                        Label("Waiting for your iPhone", systemImage: "iphone.slash")
                    }
                }
            }
            .navigationTitle("Today")
            .navigationDestination(for: UUID.self) { id in
                GoalPage(goalID: id)
            }
        }
        // Goals are drawn in the iPhone's palette, as it looks in dark mode.
        .environment(\.watchPalette, palette)
        .tint(palette.accentColor)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
        #if DEBUG
        // Simulator runs: `MOMENTUM_WATCH_GOAL` opens a goal by name once the iPhone has sent it.
        .onChange(of: snapshot.items.map(\.id)) { _, _ in openRequestedGoal() }
        .onAppear { openRequestedGoal() }
        #endif
    }

    #if DEBUG
    private func openRequestedGoal() {
        guard path.isEmpty, let name = ProcessInfo.processInfo.environment["MOMENTUM_WATCH_GOAL"],
              let item = store.snapshot.items.first(where: { $0.name == name }) else { return }
        path = [item.id]
    }
    #endif
}

private struct GoalRow: View {
    let item: WatchSnapshot.Item
    @Environment(\.watchPalette) private var palette

    var body: some View {
        // The name gets the row's full width (two lines if it needs them); the streak rides on
        // the progress line, where a column of its own cut names short.
        HStack(spacing: 10) {
            WatchRing(progress: item.progress, color: item.color, symbol: item.symbol, lineWidth: 4.5)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 6) {
                    Text(item.isComplete ? "Done" : item.progressText)
                        .foregroundStyle(item.isComplete ? AnyShapeStyle(palette.success) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if item.streak > 0 {
                        Label("\(item.streak)", systemImage: "flame.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(palette.streak)
                            .fixedSize()
                    }
                }
                .font(.caption2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

private struct SessionRow: View {
    let session: FocusSession
    let item: WatchSnapshot.Item
    @Environment(\.watchPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(item.name, systemImage: session.isRunning ? "waveform" : "pause.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.color(item.color))
                .lineLimit(1)
            SessionClock(session: session)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
        }
    }
}

private struct RestRow: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.watchPalette) private var palette
    let rest: RestPeriod
    let item: WatchSnapshot.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(rest.isLong ? "Long break" : "Break", systemImage: rest.isLong ? "cup.and.saucer.fill" : "leaf.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.rest)
            BreakClock(rest: rest)
            Button("Start block \(rest.nextBlock)") { store.perform(.startNextBlock(restStart: rest.start)) }
                .tint(palette.color(item.color))
        }
    }
}

/// A break's countdown, then word that it's over. Drawn again when the break ends: a countdown
/// stops at 0:00 and stays there until something else redraws it.
private struct BreakClock: View {
    let rest: RestPeriod

    var body: some View {
        TimelineView(.explicit([rest.end])) { context in
            // One reading of the clock for the check and the range: the end can pass between two.
            let now = max(context.date, .now)
            if rest.isOver(at: now) {
                Text("Break's over")
                    .font(.title3.weight(.semibold))
            } else {
                Text(timerInterval: now...rest.end, countsDown: true)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}

/// The running session's clock: counting down a planned block, up otherwise; frozen when paused.
/// Drawn again at the planned end, to go on counting the time so far: a countdown stops at 0:00
/// and stays there until something else redraws it.
struct SessionClock: View {
    let session: FocusSession

    var body: some View {
        TimelineView(.explicit(turnovers)) { context in
            clock(at: max(context.date, .now))
        }
        .monospacedDigit()
    }

    /// When the clock changes from counting down to counting up: a running session's planned end.
    private var turnovers: [Date] {
        session.plannedEnd.map { [$0] } ?? []
    }

    @ViewBuilder
    private func clock(at now: Date) -> some View {
        if !session.isRunning {
            // Paused: the time left of a planned session (as the iPhone shows), else the time so far.
            Text(Formatting.clock(session.remaining(at: now).map { max(0, $0) } ?? session.elapsed(at: now)))
        } else if let end = session.plannedEnd, end > now {
            Text(timerInterval: now...end, countsDown: true)
        } else {
            Text(timerInterval: session.clockStart(at: now)...Date.distantFuture, countsDown: false)
        }
    }
}

/// One goal: its ring, and the action that moves it.
struct GoalPage: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.watchPalette) private var palette
    let goalID: UUID

    var body: some View {
        if let item = store.item(goalID) {
            ScrollView {
                VStack(spacing: 10) {
                    ZStack {
                        WatchRing(progress: item.progress, color: item.color, lineWidth: 10)
                        VStack(spacing: 0) {
                            Image(systemName: item.symbol)
                                .font(.title3)
                                .foregroundStyle(palette.color(item.color))
                            if let session = store.snapshot.session, session.goalID == item.id {
                                SessionClock(session: session)
                                    .font(.system(.title3, design: .rounded, weight: .semibold))
                            }
                        }
                    }
                    .frame(width: 104, height: 104)
                    Text(item.isComplete ? item.doneText : item.progressText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    actions(for: item)
                    HStack(spacing: 10) {
                        if item.streak > 0 {
                            Label("\(item.streak) \(item.streak == 1 ? item.streakUnit : item.streakUnit + "s")", systemImage: "flame.fill")
                                .foregroundStyle(palette.streak)
                        }
                        if let day = item.challengeDay, let length = item.challengeLength {
                            Label("Day \(day)/\(length)", systemImage: "flag.fill")
                                .foregroundStyle(palette.color(item.color))
                        }
                    }
                    .font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(item.name)
            .containerBackground(palette.backdrop(item.color), for: .navigation)
            #if DEBUG
            .task { await DebugActions.runRequested(on: item, store: store) }
            #endif
            .overlay(alignment: .top) {
                if store.isSending { ProgressView().controlSize(.small) }
            }
        } else {
            ContentUnavailableView("Not today", systemImage: "calendar", description: Text("This goal isn't on today's list any more."))
        }
    }

    @ViewBuilder
    private func actions(for item: WatchSnapshot.Item) -> some View {
        let running = store.snapshot.session.map { $0.goalID == item.id }
        if item.kind == .time {
            if let session = store.snapshot.session, running == true {
                HStack(spacing: 8) {
                    Button {
                        store.perform(.setPaused(goal: item.id, sessionStart: session.startedAt, paused: session.isRunning))
                    } label: {
                        Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(session.isRunning ? "Pause" : "Resume")
                    Button {
                        store.perform(.stop(goal: item.id, sessionStart: session.startedAt))
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .tint(palette.color(item.color))
                    .accessibilityLabel("Stop")
                }
            } else {
                Button {
                    store.perform(.start(goal: item.id))
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .tint(palette.color(item.color))
                .primaryHandGesture()
            }
        } else if let title = item.actionTitle {
            Button {
                store.perform(.quickAdd(goal: item.id))
            } label: {
                Text(title)
                    .font(.headline)
            }
            .tint(palette.color(item.color))
            .primaryHandGesture()
        }
    }
}

extension View {
    /// A double tap of the fingers presses this, on watches and watchOS versions that have it.
    @ViewBuilder
    func primaryHandGesture() -> some View {
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

#if DEBUG
/// Simulator runs: `MOMENTUM_WATCH_ACTION` (`start`, `pause`, `stop` or `log`) taps that button on
/// the goal opened by `MOMENTUM_WATCH_GOAL`, once, as a test of the round trip to the iPhone.
@MainActor
enum DebugActions {
    private static var hasRun = false

    static func runRequested(on item: WatchSnapshot.Item, store: WatchStore) async {
        guard !hasRun, let action = ProcessInfo.processInfo.environment["MOMENTUM_WATCH_ACTION"] else { return }
        hasRun = true
        try? await Task.sleep(for: .seconds(2))
        let session = store.snapshot.session.flatMap { $0.goalID == item.id ? $0 : nil }
        switch action {
        case "start": store.perform(.start(goal: item.id))
        case "pause": if let session { store.perform(.setPaused(goal: item.id, sessionStart: session.startedAt, paused: session.isRunning)) }
        case "stop": if let session { store.perform(.stop(goal: item.id, sessionStart: session.startedAt)) }
        case "log": store.perform(.quickAdd(goal: item.id))
        default: break
        }
    }
}
#endif
