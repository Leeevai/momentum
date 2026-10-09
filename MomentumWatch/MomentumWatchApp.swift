import SwiftUI

@main
struct MomentumWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environment(store)
        }
    }
}
