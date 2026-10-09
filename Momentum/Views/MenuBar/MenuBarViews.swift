import AppKit
import MomentumCore
import SwiftUI

/// The menu-bar item: a live timer while focusing, otherwise today's progress.
struct MenuBarLabel: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        label
            .onReceive(NotificationCenter.default.publisher(for: .reopenMainWindow)) { _ in
                openWindow(id: "main")
            }
    }

    @ViewBuilder
    private var label: some View {
        if store.data.preferences.showsTimerInMenuBar, let session = store.data.session, let goal = store.goal(session.goalID) {
            LiveClock(isLive: session.isRunning, fallback: .now) { now in
                Text("\(goal.icon) \(label(session, now: now))")
                    .monospacedDigit()
            }
        } else {
            let summary = store.engine.todaySummary(now: store.now)
            HStack(spacing: 3) {
                Image(systemName: summary.total > 0 && summary.done == summary.total ? "flame.fill" : "flame")
                if summary.total > 0 {
                    Text("\(summary.done)/\(summary.total)")
                        .monospacedDigit()
                }
            }
        }
    }

    private func label(_ session: FocusSession, now: Date) -> String {
        let prefix = session.isRunning ? "" : "⏸ "
        if let remaining = session.remaining(at: now), remaining > 0 {
            return prefix + Formatting.clock(remaining)
        }
        return prefix + Formatting.clock(session.elapsed(at: now))
    }
}

struct MenuBarPanel: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let engine = store.engine
        let now = store.now
        let goals = store.filteredForFocus(engine.todayGoals(now: now))
        let summary = engine.todaySummary(now: now)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.headline)
                    Text("\(summary.done) of \(summary.total) done · best streak \(engine.longestCurrentStreak(now: now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let filter = store.activeFocusFilter {
                        Label("Focus: \(filter.categories.sorted().formatted(.list(type: .and)))", systemImage: "moon.fill")
                            .font(.caption2)
                            .foregroundStyle(.indigo)
                    }
                }
                Spacer()
                ProgressRing(progress: summary.total == 0 ? 0 : Double(summary.done) / Double(summary.total), color: .blue, lineWidth: 4)
                    .frame(width: 26, height: 26)
            }

            if let session = store.data.session, let goal = store.goal(session.goalID) {
                MenuSessionCard(goal: goal, session: session)
            }

            if store.data.goals.isEmpty {
                Text("No goals yet. Open Momentum to add one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if goals.isEmpty {
                Text("Nothing due today.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(goals) { MenuGoalRow(goal: $0) }
                }
            }
            .frame(maxHeight: 360)
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            HStack(spacing: 12) {
                Button {
                    openWindow(id: "main")
                    NSApp.activate()
                } label: {
                    Label("Open Momentum", systemImage: "macwindow")
                }
                Spacer()
                Button {
                    openSettings()
                    NSApp.activate()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Momentum")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
    }
}

private struct MenuSessionCard: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let session: FocusSession

    var body: some View {
        HStack(spacing: 12) {
            Text(goal.icon).font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text(goal.name).font(.callout.weight(.semibold)).lineLimit(1)
                SessionClockText(session: session)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(goal.tint)
            }
            Spacer()
            Button {
                store.togglePause()
            } label: {
                Image(systemName: session.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(CircleButtonStyle(tint: goal.tint, size: 30, prominent: false))
            Button {
                store.stopFocus()
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(CircleButtonStyle(tint: goal.tint, size: 30))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(goal.tint.opacity(0.12)))
    }
}

private struct MenuGoalRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        let engine = store.engine
        let streak = engine.streak(for: goal, now: store.now)
        HStack(spacing: 10) {
            GoalRing(goal: goal, lineWidth: 4)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(goal.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                GoalProgressText(goal: goal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            StreakBadge(count: streak.current, unit: streak.unit)
            GoalPrimaryButton(goal: goal, compact: true, iconOnly: true)
        }
    }
}
