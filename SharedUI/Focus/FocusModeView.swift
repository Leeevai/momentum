import MomentumCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The running session, full screen: a big ring and clock over a slowly breathing glow, with
/// nothing else in sight. During a Pomodoro break it shows the break, and it closes itself when
/// there's nothing left to show.
struct FocusModeView: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onClose: () -> Void

    var body: some View {
        let session = store.data.session
        let rest = store.data.rest
        let goal = (session?.goalID ?? rest?.goalID).flatMap(store.goal)
        ZStack {
            if let goal {
                VStack(spacing: 28) {
                    header(goal: goal)
                    Spacer(minLength: 0)
                    if let session {
                        SessionFace(goal: goal, session: session)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else if let rest {
                        RestFace(goal: goal, rest: rest)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                .padding(28)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Breathing(tint: goal.tint, secondary: goal.color.highlight, isCalm: rest != nil || session?.isRunning == false,
                              reduceMotion: reduceMotion)
                        .ignoresSafeArea()
                }
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: session?.startedAt)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: rest)
        .onChange(of: goal == nil) { _, gone in if gone { onClose() } }
        .onEscape(onClose)
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .statusBarHidden()
        #endif
    }

    private func header(goal: Goal) -> some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .secondaryActionStyle(.white, compact: true)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
            Spacer()
            HStack(spacing: 8) {
                GoalIcon(goal: goal, size: 28)
                Text(goal.name)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            Spacer()
            FocusSoundMenu()
                .foregroundStyle(.white)
                .frame(width: 44)
        }
    }
}

/// The ring and clock of a running session, with its controls.
private struct SessionFace: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let session: FocusSession

    var body: some View {
        let pomodoro = store.data.preferences.pomodoro
        VStack(spacing: 30) {
            LiveClock(isLive: session.isRunning, fallback: .now) { now in
                let planned = session.plannedDuration ?? 0
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.14), lineWidth: 18)
                    Circle()
                        .trim(from: 0, to: planned > 0 ? min(1, session.elapsed(at: now) / planned) : 1)
                        .stroke(LinearGradient(colors: [.white, .white.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .white.opacity(0.5), radius: 12)
                        .animation(.linear(duration: 1), value: Int(now.timeIntervalSince1970))
                    VStack(spacing: 8) {
                        Text(session.isRunning ? (pomodoro.isEnabled ? "Block \(session.block)" : "Focusing") : "Paused")
                            .font(.headline)
                            .textCase(.uppercase)
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.75))
                        SessionClockText(session: session)
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if !session.note.isEmpty {
                            Text(session.note)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(40)
                }
                .frame(width: 300, height: 300)
            }
            if pomodoro.isEnabled {
                BlockDots(done: session.block - 1, total: pomodoro.blocksPerCycle)
            }
            FocusControlCluster(goal: goal)
                .environment(\.colorScheme, .dark)
        }
    }
}

/// A Pomodoro break: its countdown, then the next block.
private struct RestFace: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let rest: RestPeriod

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let over = rest.isOver(at: context.date)
            VStack(spacing: 26) {
                Image(systemName: over ? "bell.fill" : (rest.isLong ? "cup.and.saucer.fill" : "leaf.fill"))
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: over)
                    .contentTransition(.symbolEffect(.replace))
                Text(over ? "Break's over" : (rest.isLong ? "Long break" : "Breathe out"))
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                if !over {
                    Text(Formatting.clock(rest.remaining(at: context.date)))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .clockTick(context.date)
                }
                Button {
                    store.startNextBlock()
                } label: {
                    Label("Start block \(rest.nextBlock)", systemImage: "play.fill")
                }
                .primaryActionStyle(goal.tint)
                Button(over ? "Done for now" : "Skip break") { store.endRest() }
                    .secondaryActionStyle(.white, compact: true)
            }
        }
    }
}

/// A deep field of the goal's colors with a glow that swells and settles about six times a
/// minute: something to breathe with. Still when Reduce Motion is on, slower while paused.
private struct Breathing: View {
    let tint: Color
    let secondary: Color
    let isCalm: Bool
    let reduceMotion: Bool

    var body: some View {
        // The glow is an overlay, so its size never widens the screen's layout.
        LinearGradient(colors: [tint.blended(with: .black, by: 0.55), tint.blended(with: .black, by: 0.25), secondary.blended(with: .black, by: 0.45)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                if reduceMotion {
                    glow(scale: 1)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let period = isCalm ? 14.0 : 10.0
                        let phase = (sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / period) + 1) / 2
                        glow(scale: 0.85 + 0.3 * phase)
                    }
                }
            }
            .clipped()
    }

    private func glow(scale: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [secondary.opacity(0.55), tint.opacity(0.25), .clear], center: .center, startRadius: 0, endRadius: 360))
            .frame(width: 720, height: 720)
            .scaleEffect(scale)
            .blur(radius: 30)
    }
}
