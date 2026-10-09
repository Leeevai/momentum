import MomentumCore

/// Opens `momentum://` links in the app, whatever brought them: a URL, a Home Screen quick
/// action, Spotlight. A link that arrives before the app is ready (one that launched it) waits.
@MainActor
enum LinkRouter {
    /// Shows a link; set by the app at launch.
    static var handler: ((DeepLink) -> Void)? {
        didSet {
            guard let handler, let pending else { return }
            self.pending = nil
            handler(pending)
        }
    }

    private static var pending: DeepLink?

    static func open(_ link: DeepLink) {
        if let handler { handler(link) } else { pending = link }
    }
}
