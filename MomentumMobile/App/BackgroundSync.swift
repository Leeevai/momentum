import BackgroundTasks
import Foundation
import MomentumCore
import OSLog

/// Catches up with the sync folder now and then while the app isn't open, so the widgets, the
/// Live Activity and the watch show what other devices did without the app being opened. The
/// system picks the moments, from how the app is used and whether Background App Refresh is on;
/// it's only asked while a sync folder is chosen.
enum BackgroundSync {
    /// Listed under `BGTaskSchedulerPermittedIdentifiers` in the Info.plist, as the bundle ID
    /// followed by ".sync".
    static let identifier = "\(Bundle.main.bundleIdentifier ?? "dev.momentum.Momentum").sync"
    private static let logger = Logger(subsystem: "dev.momentum.app", category: "BackgroundSync")

    /// Asks for the next refresh, half an hour away at the earliest, or withdraws it once sync is off.
    static func schedule() {
        guard FolderSync.hasFolder else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background App Refresh is off, or this is a simulator: the app catches up when opened.
            logger.info("No background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One refresh: merges the folder and passes the result on. The widgets reload with any change
    /// to the data file.
    static func refresh() async {
        schedule()
        guard FolderSync.hasFolder else { return }
        let changed = FolderSync.catchUpFromFolder()
        let data = SharedStore.load()
        // Whether or not anything came in: a new day changes what's due on the watch face.
        await WatchBridge.shared.sendAndWait(ProgressEngine(data: data).watchSnapshot(now: .now))
        // It can update or end a Live Activity from the background, not start one.
        if changed { await FocusActivityController.sync(with: data) }
    }
}
