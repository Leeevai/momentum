import MomentumCore
import SwiftUI

@main
struct MomentumMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var appDelegate
    @State private var store = Self.makeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileRoot()
                .storePalette()
                .environment(store)
                .onOpenURL { url in DeepLink(url: url).map(handle) }
                .onAppear {
                    LinkRouter.handler = { link in handle(link) }
                    GoalSpotlight.update(from: store.data)
                }
        }
        .commands { MobileCommands(store: store) }
        .onChange(of: scenePhase) { _, phase in
            // The quick actions are refreshed on the way out, so they match the day when next shown.
            if phase == .background { QuickActions.update(from: store.engine) }
            guard phase == .active else { return }
            store.reload()
            store.advancePomodoro()
            store.sync?.pull()
            store.effects.syncLiveActivity(store.data)
            store.effects.refreshFocusSound(store.data)
            // The watch hears of each change, but a new day changes what's due without one, and a
            // suspended app sees no midnight: coming forward brings the watch up to date.
            WatchBridge.shared.send(store.engine.watchSnapshot(now: .now))
        }
    }

    private static func makeStore() -> GoalStore {
        let store = makeLaunchStore()
        // Wired here, not when the window appears: woken in the background (by a widget or Lock
        // Screen button, or Siri) the app has no window, and what it changes must reach the watch.
        store.onChange = { engine in WatchBridge.shared.send(engine.watchSnapshot(now: .now)) }
        return store
    }

    /// The real store; in debug builds, `MOMENTUM_DEMO=1` swaps in demo data held in memory (`empty`
    /// for none), `MOMENTUM_DEMO=seed` writes the demo data to the real data file (for the watch
    /// and the widgets, which read that file), and
    /// `MOMENTUM_TAB` opens a tab and `MOMENTUM_SHEET` a sheet, for screenshots and simulator runs
    /// (`MOMENTUM_SHEET=import` takes the `MOMENTUM_IMPORT_*` settings in `ImportTodosSheet`).
    private static func makeLaunchStore() -> GoalStore {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["MOMENTUM_DEMO"] == "empty" {
            return GoalStore.preview(AppData())
        }
        if environment["MOMENTUM_DEMO"] == "seed" {
            SharedStore.fileStore.replace(with: AppData.demo())
            return GoalStore()
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
            case "goal":
                // MOMENTUM_GOAL picks one by name; the first goal otherwise.
                let named = data.goals.first { $0.name == environment["MOMENTUM_GOAL"] } ?? data.goals.first
                if let named { store.route = .goal(named.id) }
            default: break
            }
            switch environment["MOMENTUM_SHEET"] {
            case "new": store.sheet = .newGoal
            case "plan": store.sheet = .plan(DayID(.now))
            case "reflect": store.sheet = .reflect(DayID(.now))
            case "edit": if let first = data.goals.first { store.sheet = .editGoal(first) }
            case "focus": store.isFocusModePresented = true
            case "review": store.sheet = .review
            case "import": store.sheet = .importTodos(link: environment["MOMENTUM_IMPORT_LINK"].flatMap(TodoText.link(from:)))
            default: break
            }
            // MOMENTUM_RATING=1 shows the question asked after a session.
            if environment["MOMENTUM_RATING"] == "1", let goal = data.goals.first(where: { $0.kind == .time }) {
                store.sessionRating = SessionRating(goal: goal, entryIDs: [], seconds: 50 * 60)
            }
            return store
        }
        #endif
        return GoalStore()
    }

    private func handle(_ link: DeepLink) {
        switch link {
        case .today: store.route = .today
        case .journal: store.route = .journal
        case .insights: store.route = .insights
        case .awards: store.route = .awards
        case .plan: store.sheet = .plan(DayID(.now))
        case .reflect: store.sheet = .reflect(DayID(.now))
        case .review: store.sheet = .review
        case .goal(let id): store.select(id)
        case .focus(let id): store.focus(onGoal: id)
        case .newGoal: store.sheet = .newGoal
        case .openLink(let goalID, let linkID):
            if let link = store.goal(goalID)?.links.first(where: { $0.id == linkID }) { LinkOpener.open(link) }
        }
    }
}
