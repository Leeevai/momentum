import MomentumCore
import SwiftUI

/// Today on iPhone: the day's rings, the running timer, coach tips, the plan, and a card per goal
/// that zooms open into the goal's page. Goals that aren't due today follow, folded away, since
/// no other screen on iPhone opens a goal.
struct MobileTodayView: View {
    @Environment(GoalStore.self) private var store
    @Binding var path: [UUID]
    @Namespace private var zoom
    @State private var showsSettings = false
    /// A per-device choice, so it lives in user defaults rather than the shared data.
    @AppStorage("showsGoalsNotDueToday") private var showsNotToday = false

    var body: some View {
        let engine = store.engine
        let now = store.now
        let today = engine.stackOrdered(store.filteredForFocus(engine.todayGoals(now: now)))
        let done = today.filter { engine.isComplete($0, now: now) }
        let plan = store.data.journalEntry(for: DayID(now))
        let tips = store.coachTips
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TodayHeader(goals: today)
                    if let filter = store.activeFocusFilter {
                        FocusFilterBanner(filter: filter) {
                            withAnimation { store.ignoredFocusFilter = filter }
                        }
                    }
                    if let session = store.data.session, let goal = store.goal(session.goalID) {
                        FocusBanner(goal: goal, session: session)
                            .id(session.startedAt)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    } else if let rest = store.data.rest, let goal = store.goal(rest.goalID) {
                        RestBanner(rest: rest, goal: goal)
                            .id(rest.start)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                    if engine.activeGoals.isEmpty {
                        WelcomeView()
                    } else {
                        if !tips.isEmpty { CoachStrip(tips: tips) }
                        if let plan, plan.hasPlan { DayPlanCard(entry: plan) }
                        if !engine.timeline(on: now, now: now).isEmpty { FocusTimeline() }
                        goalSections(today: today, done: done)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: done.map(\.id))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.data.session?.goalID)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.data.rest)
            }
            .scrollContentBackground(.hidden)
            // Pull down to bring in what other devices did.
            .refreshable {
                store.reload()
                store.sync?.syncNow()
                try? await Task.sleep(for: .milliseconds(600))
            }
            .background(Aurora())
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { store.sheet = .newGoal } label: { Label("New Goal", systemImage: "target") }
                        Button { store.sheet = .importTodos(link: nil) } label: {
                            Label("To-dos from Videos", systemImage: "play.rectangle.on.rectangle")
                        }
                    } label: {
                        Label("New Goal", systemImage: "plus")
                    } primaryAction: {
                        store.sheet = .newGoal
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let goal = store.goal(id) {
                    MobileGoalPage(goal: goal)
                        .zoomTransition(id: id, in: zoom)
                }
            }
            .sheet(isPresented: $showsSettings) { MobileSettings() }
        }
    }

    /// Today's goals, then the ones on a break and the ones not due today, as on the Mac, where
    /// the sidebar lists them all.
    @ViewBuilder
    private func goalSections(today: [Goal], done: [Goal]) -> some View {
        let engine = store.engine
        let now = store.now
        let upNext = today.filter { !engine.isComplete($0, now: now) }
        let due = Set(engine.todayGoals(now: now).map(\.id))
        let resting = store.filteredForFocus(engine.activeGoals.filter { $0.isOnBreak(at: now) && !engine.isRunning($0) })
        let notToday = store.filteredForFocus(engine.activeGoals.filter { !due.contains($0.id) && !$0.isOnBreak(at: now) })
        if !upNext.isEmpty {
            section("Up next", systemImage: "arrow.forward.circle", goals: upNext)
        } else if !today.isEmpty {
            AllDoneCard(done: done.count)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
        section("Done", systemImage: "checkmark.circle", goals: done)
        if today.isEmpty && resting.isEmpty {
            Text(notToday.isEmpty ? "Nothing is due today. Enjoy the day off." : "Nothing is due today. Enjoy the day off, or get ahead on a goal below.")
                .foregroundStyle(.secondary)
        }
        if !resting.isEmpty {
            section("On a break", systemImage: "pause.circle", goals: resting)
                .opacity(0.75)
        }
        if !notToday.isEmpty {
            notTodaySection(notToday)
        }
    }

    @ViewBuilder
    private func section(_ title: String, systemImage: String, goals: [Goal]) -> some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title, systemImage: systemImage)
                    .foregroundStyle(.secondary)
                grid(goals)
            }
        }
    }

    /// Goals that aren't due today, folded away until asked for: there to open or get ahead on,
    /// without crowding the day.
    private func notTodaySection(_ goals: [Goal]) -> some View {
        let label = "Not today, \(goals.count) \(Formatting.unit("goals", for: Double(goals.count)))"
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showsNotToday.toggle() }
            } label: {
                SectionTitle("Not today", systemImage: "calendar", trailing: AnyView(notTodayCount(goals.count)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
            .accessibilityValue(showsNotToday ? "Shown" : "Hidden")
            .accessibilityHint("Shows or hides the goals that aren't due today")
            if showsNotToday {
                grid(goals)
            }
        }
    }

    private func notTodayCount(_ count: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(showsNotToday ? 90 : 0))
        }
        .font(.subheadline.weight(.semibold))
    }

    private func grid(_ goals: [Goal]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
            ForEach(goals) { goal in
                GoalCard(goal: goal) { path.append(goal.id) }
                    .zoomSource(id: goal.id, in: zoom)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
    }
}

/// Shown in place of Up next once everything due today is done.
private struct AllDoneCard: View {
    let done: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.success.gradient)
                .symbolEffect(.bounce, value: done)
            VStack(alignment: .leading, spacing: 2) {
                Text("Everything is done for today")
                    .font(.headline)
                Text("That's how momentum is built. See you tomorrow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: .success, highlighted: false)
        .accessibilityElement(children: .combine)
    }
}

/// A goal's page on iPhone, with its actions in the navigation bar.
struct MobileGoalPage: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        ScrollView {
            GoalDetailContent(goal: goal)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Aurora(accent: goal.tint))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { store.sheet = .editGoal(goal) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                    GoalContextMenu(goal: goal)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }
}

extension View {
    /// The source a navigation zoom grows from (iOS 18 and later).
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Zooms a pushed page out of its source, and back into it on the way back (iOS 18 and later).
    @ViewBuilder
    func zoomTransition(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
