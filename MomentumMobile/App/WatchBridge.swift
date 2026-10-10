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

    /// Everything below is touched only on this queue.
    private let queue = DispatchQueue(label: "momentum.watch-bridge")
    private var lastSent: Data?
    /// What the watch face last got, to spend the day's complication budget only on changes
    /// that show there.
    private var lastFace: FaceState?
    private static let appliedKey = "watchAppliedCommands"
    private static let appliedLimit = 200

    private struct FaceState: Equatable {
        var day: DayID
        var done: Int
        var total: Int
        /// The timer as the face draws it: which session, whether it's paused, and where its clock
        /// starts and ends, which adding time or a pause moves. Not its note, which isn't shown.
        var session: FocusSession?

        init(_ snapshot: WatchSnapshot) {
            day = snapshot.day
            done = snapshot.done
            total = snapshot.total
            session = snapshot.session
            session?.note = ""
        }
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends today's snapshot, if a watch app is there to show it and it changed.
    func send(_ snapshot: WatchSnapshot) {
        guard WCSession.isSupported() else { return }
        queue.async { [self] in deliver(snapshot) }
    }

    /// `pushesFace` is false when the watch asked (it gets the snapshot in the reply and reloads
    /// its own complications), so the day's few complication pushes go to changes made elsewhere.
    private func deliver(_ snapshot: WatchSnapshot, pushesFace: Bool = true) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled,
              let encoded = try? snapshot.encoded(), encoded != lastSent else { return }
        do {
            try session.updateApplicationContext([Key.snapshot: encoded])
            lastSent = encoded
        } catch {
            print("Could not update the watch: \(error)")
        }
        // The application context reaches the watch app when it next runs; a complication on the
        // face needs a push of its own, which wakes it (a limited number of times a day).
        let face = FaceState(snapshot)
        guard face != lastFace else { return }
        // The remaining count is zero when none of the app's complications is on the face. Not
        // `isComplicationEnabled`: that stays false for a WidgetKit complication that is there.
        if !pushesFace {
            lastFace = face
        } else if session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo([Key.snapshot: encoded])
            lastFace = face
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
        queue.async { [self] in
            lastSent = nil
            lastFace = nil
        }
        session.activate()
    }

    /// The watch app was installed (or the complication added): bring it up to date now, rather
    /// than at the next change.
    func sessionWatchStateDidChange(_ session: WCSession) {
        queue.async { [self] in
            lastSent = nil
            lastFace = nil
            deliver(currentSnapshot())
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        queue.async { [self] in
            let snapshot = handle(message)
            replyHandler((try? snapshot.encoded()).map { [Key.snapshot: $0] } ?? [:])
            deliver(snapshot, pushesFace: false)
        }
    }

    /// Commands queued while the phone was out of reach arrive here, in order.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        queue.async { [self] in deliver(handle(userInfo)) }
    }

    /// Carries out a command, once however often it arrives, and returns the snapshot after it.
    /// A message without one asks for a fresh snapshot.
    private func handle(_ message: [String: Any]) -> WatchSnapshot {
        guard let raw = message[Key.action] as? Data, let command = try? WatchCommand(encoded: raw) else {
            return currentSnapshot()
        }
        var applied = UserDefaults.standard.stringArray(forKey: Self.appliedKey) ?? []
        guard !applied.contains(command.id.uuidString) else { return currentSnapshot() }
        LiveActivitySync.catchUp()
        let data = SharedStore.update { $0.apply(command) }
        applied.append(command.id.uuidString)
        UserDefaults.standard.set(Array(applied.suffix(Self.appliedLimit)), forKey: Self.appliedKey)
        Task { await LiveActivitySync.after(data) }
        return ProgressEngine(data: data).watchSnapshot(now: .now)
    }
}
