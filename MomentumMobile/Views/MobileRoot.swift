import MomentumCore
import SwiftUI

/// The iPhone and iPad app: a tab for each part, the Liquid Glass tab bar on iOS 26.
struct MobileRoot: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var tab: MobileTab = .today
    @State private var todayPath: [UUID] = []

    var body: some View {
        @Bindable var store = store
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
        .sheet(item: $store.sheet) { route in
            MobileSheet(route: route)
        }
        .overlay {
            if let celebration = store.celebration {
                CelebrationOverlay(celebration: celebration) { store.celebration = nil }
                    .id(celebration.id)
            }
        }
        .overlay {
            if let toast = store.toast {
                ToastBanner(toast: toast)
                    .id(toast.id)
            }
        }
        .onAppear {
            store.undoManager = undoManager
            follow(store.route)
        }
        .onChange(of: undoManager) { _, manager in store.undoManager = manager }
        .onChange(of: store.route) { _, route in follow(route) }
        .onChange(of: tab) { _, tab in
            // Keep the store's idea of where we are in step, so routes set elsewhere still fire.
            if tab != .today || todayPath.isEmpty { store.route = tab.route }
        }
        .onChange(of: todayPath) { _, path in
            if path.isEmpty, case .goal = store.route { store.route = .today }
        }
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
            }
        }
        .presentationDragIndicator(.visible)
    }
}
