import MomentumCore
import SwiftUI

@main
struct MomentumMobileApp: App {
    @State private var store = Self.makeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileRoot()
                .environment(store)
                .onOpenURL { url in handle(url) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.reload()
            store.advancePomodoro()
            store.sync?.pull()
            store.effects.syncLiveActivity(store.data)
            store.effects.refreshFocusSound(store.data)
        }
    }

    /// The real store; in debug builds, `MOMENTUM_DEMO=1` swaps in demo data held in memory (`empty`
    /// for none), and
    /// `MOMENTUM_TAB` opens a tab and `MOMENTUM_SHEET` a sheet, for screenshots and simulator runs.
    private static func makeStore() -> GoalStore {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["MOMENTUM_DEMO"] == "empty" {
            return GoalStore.preview(AppData())
        }
        if environment["MOMENTUM_DEMO"] == "1" {
            var data = AppData.demo()
            if let deepWork = data.goals.first(where: { $0.name == "Deep work" }) {
                data.session = FocusSession(goalID: deepWork.id, plannedDuration: 50 * 60, start: .now.addingTimeInterval(-32 * 60))
            }
            let store = GoalStore.preview(data)
            switch environment["MOMENTUM_TAB"] {
            case "journal": store.route = .journal
            case "insights": store.route = .insights
            case "awards": store.route = .awards
            case "goal": if let first = data.goals.first { store.route = .goal(first.id) }
            default: break
            }
            switch environment["MOMENTUM_SHEET"] {
            case "new": store.sheet = .newGoal
            case "plan": store.sheet = .plan(DayID(.now))
            case "reflect": store.sheet = .reflect(DayID(.now))
            case "edit": if let first = data.goals.first { store.sheet = .editGoal(first) }
            case "focus": store.isFocusModePresented = true
            case "review": store.sheet = .review
            default: break
            }
            return store
        }
        #endif
        return GoalStore()
    }

    private func handle(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .today: store.route = .today
        case .journal: store.route = .journal
        case .insights: store.route = .insights
        case .awards: store.route = .awards
        case .plan: store.sheet = .plan(DayID(.now))
        case .reflect: store.sheet = .reflect(DayID(.now))
        case .review: store.sheet = .review
        case .goal(let id): store.select(id)
        case .newGoal: store.sheet = .newGoal
        case .openLink(let goalID, let linkID):
            if let link = store.goal(goalID)?.links.first(where: { $0.id == linkID }) { LinkOpener.open(link) }
        }
    }
}
