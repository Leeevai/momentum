import UIKit

/// Starts what has to run at launch, before any window: the watch link, and the scene delegate
/// that receives Home Screen quick actions.
final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    /// The watch link starts here, at launch: a tap on the watch can wake the app in the
    /// background, with no window, and the message only arrives once the session is active.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        WatchBridge.shared.activate()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}
