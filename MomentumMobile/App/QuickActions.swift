import MomentumCore
import SwiftUI
import UIKit

/// The Home Screen quick actions (touch and hold the app icon): focus on the goals that still
/// need it today, plan or reflect on the day, add a goal. Each is a `momentum://` link, handled
/// like any other.
@MainActor
enum QuickActions {
    /// Opens a link; set by the app once its views are up. A link from an action that launched
    /// the app waits here until then.
    static var handler: ((URL) -> Void)? {
        didSet {
            guard let handler, let pending else { return }
            self.pending = nil
            handler(pending)
        }
    }

    private static var pending: URL?
    private static let urlKey = "url"

    static func perform(_ item: UIApplicationShortcutItem) {
        guard let string = item.userInfo?[urlKey] as? String, let url = URL(string: string) else { return }
        if let handler { handler(url) } else { pending = url }
    }

    /// Rebuilds the actions from the current data; the system shows at most four.
    static func update(from engine: ProgressEngine, now: Date = .now) {
        UIApplication.shared.shortcutItems = items(from: engine, now: now)
    }

    private static func items(from engine: ProgressEngine, now: Date) -> [UIApplicationShortcutItem] {
        var items: [UIApplicationShortcutItem] = []
        if let session = engine.data.session, let goal = engine.goal(session.goalID) {
            items.append(item(goal.name, subtitle: session.isRunning ? "Focusing now" : "Paused",
                              symbol: "timer", link: .goal(goal.id)))
        }
        let focusable = engine.todayGoals(now: now).filter { goal in
            goal.kind == .time && !engine.isRunning(goal) && !engine.isMet(goal, periodContaining: now, now: now)
        }
        for goal in focusable.prefix(2) {
            items.append(item("Focus on \(goal.name)", subtitle: remainingText(goal, engine: engine, now: now),
                              symbol: "play.circle", link: .focus(goal.id)))
        }
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 18 {
            items.append(item("Reflect on Today", subtitle: nil, symbol: "moon.stars", link: .reflect))
        } else if hour < 12 {
            items.append(item("Plan Your Day", subtitle: nil, symbol: "sun.horizon", link: .plan))
        }
        items.append(item("New Goal", subtitle: nil, symbol: "plus", link: .newGoal))
        return Array(items.prefix(4))
    }

    private static func remainingText(_ goal: Goal, engine: ProgressEngine, now: Date) -> String {
        let left = engine.target(for: goal) - engine.amount(for: goal, on: now, now: now)
        return left > 0 ? "\(goal.format(left)) to go today" : "Start a session"
    }

    private static func item(_ title: String, subtitle: String?, symbol: String, link: DeepLink) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: "focus.momentum.\(link.url.host() ?? "open")", localizedTitle: title,
                                  localizedSubtitle: subtitle, icon: UIApplicationShortcutIcon(systemImageName: symbol),
                                  userInfo: [urlKey: link.url.absoluteString as NSString])
    }
}

/// Hands quick actions to `QuickActions`, both the one that launched the app and later ones.
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem else { return }
        MainActor.assumeIsolated { QuickActions.perform(item) }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        await MainActor.run { QuickActions.perform(shortcutItem) }
        return true
    }
}

final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}
