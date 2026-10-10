import MomentumCore
import SwiftUI

struct TodayView: View {
    @Environment(GoalStore.self) private var store
    /// A per-Mac convenience, so it lives in user defaults rather than the shared data.
    @AppStorage("dismissedWidgetTip") private var dismissedWidgetTip = false
    /// Ties a card's ring, title and glass to its opened page, so one morphs into the other.
    @Namespace private var hero
    @State private var expanded: UUID?

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 16)]
    static let morph = Animation.spring(response: 0.5, dampingFraction: 0.86)

    var body: some View {
        let engine = store.engine
        let now = store.now
        let today = engine.stackOrdered(store.filteredForFocus(engine.todayGoals(now: now)))
        let plan = store.data.journalEntry(for: DayID(now))
        let tips = store.coachTips
        let hasTimeline = !engine.timeline(on: now, now: now).isEmpty
        let upNext = today.filter { !engine.isComplete($0, now: now) }
        let done = today.filter { engine.isComplete($0, now: now) }
        let resting = store.filteredForFocus(engine.activeGoals.filter { $0.isOnBreak(at: now) && !engine.isRunning($0) })

        ZStack {
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
                    } else if let rest = store.data.rest, let goal = store.goal(rest.goalID) {
                        RestBanner(rest: rest, goal: goal)
                            .id(rest.start)
                            .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
                    }

                    if !tips.isEmpty && !engine.activeGoals.isEmpty {
                        CoachStrip(tips: tips)
                    }

                    if let plan, plan.hasPlan {
                        DayPlanCard(entry: plan)
                            .transition(.scale(scale: 0.97).combined(with: .opacity))
                    }

                    if hasTimeline {
                        FocusTimeline()
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
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.data.rest)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: plan)
            }
            .scrollContentBackground(.hidden)
            .scrollDisabled(expanded != nil)

            if let id = expanded, let goal = store.goal(id) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                    .transition(.opacity)
                ExpandedGoal(goal: goal, hero: hero, onClose: close) {
                    close()
                    store.select(id)
                }
                .zIndex(1)
            }
        }
        .background(Aurora())
        .navigationTitle("Today")
        .onChange(of: store.route) { _, _ in expanded = nil }
    }

    private func open(_ goal: Goal) {
        withAnimation(Self.morph) { expanded = goal.id }
    }

    private func close() {
        withAnimation(Self.morph) { expanded = nil }
    }

    private func section(_ title: String, systemImage: String, goals: [Goal]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(goals) { goal in
                    // The opened card leaves a same-sized space, and its parts morph into the page.
                    GoalCard(goal: goal, hero: expanded == goal.id ? nil : hero) { open(goal) }
                        .opacity(expanded == goal.id ? 0 : 1)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
    }

    private var allDoneBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.success.gradient)
                .symbolEffect(.bounce, value: store.engine.todaySummary(now: store.now).done)
            VStack(alignment: .leading, spacing: 2) {
                Text("Everything is done for today")
                    .font(.title3.weight(.semibold))
                Text("That's how momentum is built. See you tomorrow.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .success, highlighted: false)
    }
}

/// A goal's page, opened from its Today card in place. Its glass, ring and title morph from the
/// card's; Escape, the close button or a click outside morphs it back.
private struct ExpandedGoal: View {
    let goal: Goal
    let hero: Namespace.ID
    var onClose: () -> Void
    var onOpenPage: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ScrollView {
            GoalDetailContent(goal: goal, hero: hero)
                .padding(28)
                .padding(.top, 8)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Aurora(accent: goal.tint)
            }
            .clipShape(shape)
            .heroMatch("card-\(goal.id)", in: hero)
        }
        .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
        .overlay(alignment: .topTrailing) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: onOpenPage) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .secondaryActionStyle(.secondary, compact: true)
                    .help("Open as a page")
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .secondaryActionStyle(.secondary, compact: true)
                    .keyboardShortcut(.cancelAction)
                    .help("Close (Esc)")
                }
            }
            .padding(16)
        }
        .padding(18)
        .onExitCommand(perform: onClose)
    }
}

/// Points first-time users at the desktop widgets.
private struct WidgetTip: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 28))
                .foregroundStyle(LinearGradient(colors: [.swatch(.orange), .swatch(.pink)], startPoint: .top, endPoint: .bottom))
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
                .secondaryActionStyle(.swatch(.orange), compact: true)
        }
        .glassCard(tint: .swatch(.orange))
    }
}
