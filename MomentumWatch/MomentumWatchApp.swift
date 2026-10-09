import SwiftUI

@main
struct MomentumWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environment(store)
        }
        // A complication update from the iPhone wakes the app in the background to receive it.
        .backgroundTask(.watchConnectivity) {
            await store.finishPendingDeliveries()
        }
    }
}
