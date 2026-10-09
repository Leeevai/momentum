import MomentumCore
import SwiftUI

/// Today on the watch: the timer if one is running, then each goal with its ring.
struct WatchRoot: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let snapshot = store.snapshot
        NavigationStack {
            List {
                if let session = snapshot.session, let item = snapshot.item(session.goalID) {
                    Section {
                        NavigationLink(value: item.id) {
                            SessionRow(session: session, item: item)
                        }
                        .listItemTint(item.color.color.opacity(0.35))
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refresh() }
        }
    }
}

private struct GoalRow: View {
    let item: WatchSnapshot.Item

    var body: some View {
        HStack(spacing: 10) {
            WatchRing(progress: item.progress, color: item.color, symbol: item.symbol, lineWidth: 4.5)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.isComplete ? "Done" : item.progressText)
                    .font(.caption2)
                    .foregroundStyle(item.isComplete ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.streak > 0 {
                Label("\(item.streak)", systemImage: "flame.fill")
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SessionRow: View {
    let session: FocusSession
    let item: WatchSnapshot.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(item.name, systemImage: session.isRunning ? "waveform" : "pause.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.color.color)
                .lineLimit(1)
            SessionClock(session: session)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
        }
    }
}

private struct RestRow: View {
    @Environment(WatchStore.self) private var store
    let rest: RestPeriod
    let item: WatchSnapshot.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(rest.isLong ? "Long break" : "Break", systemImage: rest.isLong ? "cup.and.saucer.fill" : "leaf.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.mint)
            if rest.isOver(at: .now) {
                Text("Break's over")
                    .font(.title3.weight(.semibold))
            } else {
                Text(timerInterval: Date.now...rest.end, countsDown: true)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Button("Start block \(rest.nextBlock)") { store.perform(.startNextBlock) }
                .tint(item.color.color)
        }
    }
}

/// The running session's clock: counting down a planned block, up otherwise; frozen when paused.
struct SessionClock: View {
    let session: FocusSession

    var body: some View {
        Group {
            if !session.isRunning {
                Text(Formatting.clock(session.elapsed(at: .now)))
            } else if let end = session.plannedEnd, end > .now {
                Text(timerInterval: Date.now...end, countsDown: true)
            } else {
                Text(timerInterval: session.clockStart()...Date.distantFuture, countsDown: false)
            }
        }
        .monospacedDigit()
    }
}

/// One goal: its ring, and the action that moves it.
struct GoalPage: View {
    @Environment(WatchStore.self) private var store
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
                                .foregroundStyle(item.color.color)
                            if let session = store.snapshot.session, session.goalID == item.id {
                                SessionClock(session: session)
                                    .font(.system(.title3, design: .rounded, weight: .semibold))
                            }
                        }
                    }
                    .frame(width: 104, height: 104)
                    Text(item.isComplete ? "Done for today" : item.progressText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    actions(for: item)
                    HStack(spacing: 10) {
                        if item.streak > 0 {
                            Label("\(item.streak) \(item.streak == 1 ? item.streakUnit : item.streakUnit + "s")", systemImage: "flame.fill")
                                .foregroundStyle(.orange)
                        }
                        if let day = item.challengeDay, let length = item.challengeLength {
                            Label("Day \(day)/\(length)", systemImage: "flag.fill")
                                .foregroundStyle(item.color.color)
                        }
                    }
                    .font(.caption2.weight(.semibold))
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(item.name)
            .containerBackground(item.color.backdrop, for: .navigation)
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
                        store.perform(.togglePause)
                    } label: {
                        Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(session.isRunning ? "Pause" : "Resume")
                    Button {
                        store.perform(.stopFocus)
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .tint(item.color.color)
                    .accessibilityLabel("Stop")
                }
            } else {
                Button {
                    store.perform(.toggleFocus(goal: item.id))
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .tint(item.color.color)
                .primaryHandGesture()
            }
        } else if let title = item.actionTitle {
            Button {
                store.perform(.quickAdd(goal: item.id))
            } label: {
                Text(title)
                    .font(.headline)
            }
            .tint(item.color.color)
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
