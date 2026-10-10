import MomentumCore
import SwiftUI

struct RootView: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            detail
                .frame(minWidth: 560)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.sheet = .newGoal
                } label: {
                    Label("New Goal", systemImage: "plus")
                }
                .help("New goal (⌘N)")
            }
        }
        .sheet(item: $store.sheet) { route in
            SheetContent(route: route)
        }
        .overlay {
            if let celebration = store.celebration {
                CelebrationOverlay(celebration: celebration) { store.celebration = nil }
                    .id(celebration.id)
            }
        }
        .overlay {
            if store.isFocusModePresented {
                FocusModeView { withAnimation(.easeInOut(duration: 0.35)) { store.isFocusModePresented = false } }
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.isFocusModePresented)
        .overlay {
            if let toast = store.toast {
                ToastBanner(toast: toast)
                    .id(toast.id)
            }
        }
        .sessionRatingOverlay(store, bottomInset: 20)
        .confirmationDialog(
            "Delete \(store.confirmingDelete?.name ?? "goal")?",
            isPresented: Binding(get: { store.confirmingDelete != nil }, set: { if !$0 { store.confirmingDelete = nil } }),
            presenting: store.confirmingDelete
        ) { goal in
            Button("Delete Goal", role: .destructive) { store.delete(goal) }
            Button("Archive Instead") { store.archive(goal) }
        } message: { _ in
            Text("This removes the goal and all of its history. You can undo it with ⌘Z, or archive the goal to keep its history.")
        }
        .onAppear { store.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in store.undoManager = manager }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.route {
        case .goal(let id):
            if let goal = store.goal(id) {
                GoalDetailView(goal: goal)
                    .id(id)
            } else {
                TodayView()
            }
        case .insights:
            InsightsView()
        case .journal:
            JournalView()
        case .awards:
            AwardsView()
        case .today, nil:
            TodayView()
        }
    }
}

private struct SheetContent: View {
    @Environment(GoalStore.self) private var store
    let route: SheetRoute

    var body: some View {
        switch route {
        case .quickActions:
            QuickActionsView()
        case .newGoal:
            NewGoalFlow()
        case .importTodos(let link):
            ImportTodosSheet(initialLink: link)
        case .editGoal(let goal):
            GoalEditor(goal: goal, isNew: false)
        case .log(let goalID, let entry, let day):
            if let goal = store.goal(goalID) { LogProgressSheet(goal: goal, entry: entry, day: day) }
        case .link(let goalID, let link):
            LinkEditor(goalID: goalID, link: link)
        case .book(let goalID, let book):
            BookEditor(goalID: goalID, book: book)
        case .share(let goal):
            ShareCardSheet(goal: goal)
        case .plan(let day):
            PlanSheet(day: day)
        case .reflect(let day):
            ReflectSheet(day: day)
        case .review:
            WeekReviewSheet()
        }
    }
}
