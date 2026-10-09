import Foundation
import MomentumCore
import WatchConnectivity

/// The link to the Apple Watch app. It sends the watch a snapshot of today whenever the data
/// changes, and carries out what's tapped there. A tap on the watch wakes this app in the
/// background if it isn't running, and the change goes straight to the shared data file, as a
/// widget's would.
final class WatchBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchBridge()

    private typealias Key = WatchMessageKey

    private let queue = DispatchQueue(label: "momentum.watch-bridge")
    private var lastSent: Data?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends today's snapshot, if a watch app is there to show it and it changed.
    func send(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported() else { return }
        queue.async { [self] in
            let session = WCSession.default
            guard session.activationState == .activated, session.isWatchAppInstalled,
                  let encoded = try? snapshot.encoded(), encoded != lastSent else { return }
            do {
                try session.updateApplicationContext([Key.snapshot: encoded])
                lastSent = encoded
            } catch {
                print("Could not update the watch: \(error)")
            }
        }
    }

    private func currentSnapshot() -> WatchSnapshot {
        ProgressEngine(data: SharedStore.load()).watchSnapshot(now: .now)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { send(currentSnapshot()) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Another watch was paired: start over with it.
    func sessionDidDeactivate(_ session: WCSession) {
        queue.async { [self] in lastSent = nil }
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let snapshot = handle(message)
        guard let encoded = try? snapshot.encoded() else {
            replyHandler([:])
            return
        }
        replyHandler([Key.snapshot: encoded])
        send(snapshot)
    }

    /// Actions queued while the phone was out of reach arrive here, in order.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        send(handle(userInfo))
    }

    /// Carries out an action (or just answers a refresh) and returns the snapshot after it.
    private func handle(_ message: [String: Any]) -> WatchSnapshot {
        guard let raw = message[Key.action] as? Data, let action = try? WatchAction(encoded: raw) else {
            return currentSnapshot()
        }
        LiveActivitySync.catchUp()
        let data = SharedStore.update { $0.apply(action) }
        Task { await LiveActivitySync.after(data) }
        return ProgressEngine(data: data).watchSnapshot(now: .now)
    }
}
