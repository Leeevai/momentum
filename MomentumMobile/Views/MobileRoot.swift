import MomentumCore
import SwiftUI

/// The iPhone and iPad app: a tab for each part, the Liquid Glass tab bar on iOS 26.
struct MobileRoot: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var tab: MobileTab = .today
    @State private var todayPath: [UUID] = []

    // The body is split up so the compiler checks each part on its own: as one long chain it
    // gives up ("unable to type-check this expression in reasonable time") on Xcode 26.
    var body: some View {
        routing(presentations(tabs))
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            MobileTodayView(path: $todayPath)
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(MobileTab.today)
            NavigationStack { JournalView() }
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }
                .tag(MobileTab.journal)
            NavigationStack { InsightsView() }
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
                .tag(MobileTab.insights)
            NavigationStack { AwardsView() }
                .tabItem { Label("Awards", systemImage: "trophy.fill") }
                .badge(newAwards)
                .tag(MobileTab.awards)
        }
        .sidebarOnWideScreens()
    }

    /// Sheets, the Focus cover, celebrations, toasts and the delete confirmation.
    private func presentations(_ content: some View) -> some View {
        let bindable = Bindable(store)
        return content
            .sheet(item: bindable.sheet) { route in
                MobileSheet(route: route)
            }
            .fullScreenCover(isPresented: bindable.isFocusModePresented) {
                FocusModeView { store.isFocusModePresented = false }
                    .environment(store)
            }
            .overlay { celebrationOverlay }
            .overlay { toastOverlay }
            .confirmationDialog(deleteTitle, isPresented: isConfirmingDelete, titleVisibility: .visible,
                                presenting: store.confirmingDelete) { goal in
                Button("Delete Goal", role: .destructive) { store.delete(goal) }
                Button("Archive Instead") { store.archive(goal) }
            } message: { _ in
                Text("This removes the goal and all of its history. Archive it instead to keep its history.")
            }
    }

    /// Keeps the selected tab, the Today path and the store's route in step both ways.
    private func routing(_ content: some View) -> some View {
        content
            .onAppear {
                store.undoManager = undoManager
                follow(store.route)
            }
            .onChange(of: undoManager) { _, manager in store.undoManager = manager }
            .onChange(of: store.route) { _, route in follow(route) }
            .onChange(of: tab) { _, tab in
                // Keep the store's idea of where we are in step, so routes set elsewhere still fire.
                store.route = route(for: tab)
            }
            .onChange(of: todayPath) { _, path in
                guard tab == .today else { return }
                store.route = path.last.map(Route.goal) ?? .today
            }
    }

    @ViewBuilder private var celebrationOverlay: some View {
        if let celebration = store.celebration {
            CelebrationOverlay(celebration: celebration) { store.celebration = nil }
                .id(celebration.id)
        }
    }

    @ViewBuilder private var toastOverlay: some View {
        if let toast = store.toast {
            ToastBanner(toast: toast)
                .id(toast.id)
        }
    }

    private var deleteTitle: String {
        "Delete \(store.confirmingDelete?.name ?? "goal")?"
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(get: { store.confirmingDelete != nil }, set: { if !$0 { store.confirmingDelete = nil } })
    }

    private func route(for tab: MobileTab) -> Route {
        guard tab == .today else { return tab.route }
        return todayPath.last.map(Route.goal) ?? .today
    }

    /// Awards earned in the last day, as a badge on the tab.
    private var newAwards: Int {
        let since = Date().addingTimeInterval(-86_400)
        return store.data.achievements.values.filter { $0 > since }.count
    }

    private func follow(_ route: Route?) {
        switch route {
        case .goal(let id):
            tab = .today
            if todayPath.last != id { todayPath = [id] }
        case .journal: tab = .journal
        case .insights: tab = .insights
        case .awards: tab = .awards
        case .today:
            tab = .today
            if !todayPath.isEmpty { todayPath = [] }
        case nil:
            break
        }
    }
}

enum MobileTab: Hashable {
    case today, journal, insights, awards

    var route: Route {
        switch self {
        case .today: .today
        case .journal: .journal
        case .insights: .insights
        case .awards: .awards
        }
    }
}

/// The sheets the store asks for, presented the iPhone way.
struct MobileSheet: View {
    @Environment(GoalStore.self) private var store
    let route: SheetRoute

    var body: some View {
        Group {
            switch route {
            case .quickActions, .newGoal:
                NewGoalFlow()
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
        .presentationDragIndicator(.visible)
    }
}

extension View {
    /// The tab bar becomes a sidebar on iPad (iOS 18 and later); a phone keeps the tab bar.
    @ViewBuilder
    func sidebarOnWideScreens() -> some View {
        if #available(iOS 18.0, *) {
            tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }
}
