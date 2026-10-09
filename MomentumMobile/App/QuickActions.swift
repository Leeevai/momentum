import MomentumCore
import SwiftUI
import UIKit

/// The Home Screen quick actions (touch and hold the app icon): focus on the goals that still
/// need it today, plan or reflect on the day, add a goal. Each is a `momentum://` link, opened
/// through `LinkRouter` like any other.
@MainActor
enum QuickActions {
    private static let urlKey = "url"

    static func perform(_ item: UIApplicationShortcutItem) {
        guard let string = item.userInfo?[urlKey] as? String, let url = URL(string: string),
              let link = DeepLink(url: url) else { return }
        LinkRouter.open(link)
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
        // Not "plan" or "reflect": the actions are only rebuilt when the app goes to the
        // background, which can be hours before they're shown.
        items.append(item("Journal", subtitle: nil, symbol: "book.closed", link: .journal))
        items.append(item("New Goal", subtitle: nil, symbol: "plus", link: .newGoal))
        return Array(items.prefix(4))
    }

    /// "45m to go today", "3h to go this week".
    private static func remainingText(_ goal: Goal, engine: ProgressEngine, now: Date) -> String {
        let left = engine.target(for: goal) - engine.currentAmount(for: goal, now: now)
        guard left > 0 else { return "Start a session" }
        let period = goal.effectivePeriod == .total ? "" : " " + goal.effectivePeriod.currentLabel.lowercased()
        return "\(goal.format(left)) to go\(period)"
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
