import MomentumCore
import SwiftUI

/// Today on iPhone: the day's rings, the running timer, coach tips, the plan, and a card per goal
/// that zooms open into the goal's page.
struct MobileTodayView: View {
    @Environment(GoalStore.self) private var store
    @Binding var path: [UUID]
    @Namespace private var zoom
    @State private var showsSettings = false

    var body: some View {
        let engine = store.engine
        let now = store.now
        let today = engine.stackOrdered(store.filteredForFocus(engine.todayGoals(now: now)))
        let upNext = today.filter { !engine.isComplete($0, now: now) }
        let done = today.filter { engine.isComplete($0, now: now) }
        let plan = store.data.journalEntry(for: DayID(now))
        let tips = store.coachTips
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TodayHeader(goals: today)
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
                        section("Up next", systemImage: "arrow.forward.circle", goals: upNext)
                        section("Done", systemImage: "checkmark.circle", goals: done)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: done.map(\.id))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.data.session?.goalID)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: store.data.rest)
            }
            .scrollContentBackground(.hidden)
            .background(LivingBackdrop(primary: .accentColor, secondary: .purple))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.sheet = .newGoal } label: { Label("New Goal", systemImage: "plus") }
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

    @ViewBuilder
    private func section(_ title: String, systemImage: String, goals: [Goal]) -> some View {
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title, systemImage: systemImage)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(goals) { goal in
                        GoalCard(goal: goal) { path.append(goal.id) }
                            .zoomSource(id: goal.id, in: zoom)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                }
            }
        }
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
        .background(LivingBackdrop(primary: goal.tint, secondary: goal.color.highlight))
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
