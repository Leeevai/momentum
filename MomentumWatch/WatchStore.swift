import Foundation
import MomentumCore
import Observation
import WatchConnectivity
import WidgetKit

/// The watch's side of the link to the iPhone: the latest snapshot of today, kept for when the
/// phone is out of reach, and the commands tapped here, sent back to be carried out.
@MainActor
@Observable
final class WatchStore: NSObject {
    /// The last snapshot from the iPhone, as received.
    private var received: WatchSnapshot
    /// A command is on its way to the phone.
    private(set) var isSending = false
    /// Commands waiting for the phone to come back in reach.
    private(set) var queuedActions = 0
    private(set) var isReachable = false

    @ObservationIgnored private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private typealias Key = WatchMessageKey

    override init() {
        received = WatchSnapshotStore.load() ?? WatchSnapshot()
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// The snapshot as it stands today: one from yesterday shows daily goals starting over.
    var snapshot: WatchSnapshot { received.current(on: DayID(.now)) }

    func item(_ id: UUID) -> WatchSnapshot.Item? { snapshot.item(id) }

    /// Asks the phone for a fresh snapshot, if it's in reach.
    func refresh() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([Key.refresh: true]) { [weak self] reply in
            Task { @MainActor in self?.receive(reply) }
        } errorHandler: { _ in }
    }

    /// Sends what was tapped, dated now. Straight to the phone when it's in reach and nothing
    /// is queued ahead of it; otherwise in the queue, so commands arrive in the order tapped.
    func perform(_ action: WatchAction) {
        guard let session, session.activationState == .activated,
              let encoded = try? WatchCommand(action: action, date: .now).encoded() else { return }
        let message: [String: Any] = [Key.action: encoded]
        guard session.isReachable, session.outstandingUserInfoTransfers.isEmpty else {
            queue(message, on: session)
            return
        }
        isSending = true
        session.sendMessage(message) { [weak self] reply in
            Task { @MainActor in
                self?.isSending = false
                self?.receive(reply)
            }
        } errorHandler: { [weak self] _ in
            // The phone may have carried it out and only the reply was lost; the command's id
            // makes sending it again safe.
            Task { @MainActor in
                self?.isSending = false
                self?.queue(message, on: session)
            }
        }
    }

    /// Hands a command to the system to deliver when the phone is back, in order.
    private func queue(_ message: [String: Any], on session: WCSession) {
        session.transferUserInfo(message)
        queuedActions = session.outstandingUserInfoTransfers.count
    }

    fileprivate func receive(_ payload: [String: Any]) {
        guard let data = payload[Key.snapshot] as? Data, let snapshot = try? WatchSnapshot(encoded: data),
              snapshot.generatedAt >= received.generatedAt else { return }
        received = snapshot
        WatchSnapshotStore.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    fileprivate func update(reachable: Bool, pending: Int) {
        isReachable = reachable
        queuedActions = pending
        if reachable { refresh() }
    }

    /// Keeps a background delivery running until what's pending has arrived: the system wakes
    /// the app for a complication update and suspends it when this returns.
    func finishPendingDeliveries() async {
        guard let session else { return }
        for _ in 0..<40 where session.hasContentPending {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let reachable = session.isReachable
        let pending = session.outstandingUserInfoTransfers.count
        Task { @MainActor in
            self.receive(context)
            self.update(reachable: reachable, pending: pending)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    /// A complication update pushed by the iPhone.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.receive(userInfo) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        let pending = session.outstandingUserInfoTransfers.count
        Task { @MainActor in self.update(reachable: reachable, pending: pending) }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let pending = session.outstandingUserInfoTransfers.count
        let reachable = session.isReachable
        Task { @MainActor in self.update(reachable: reachable, pending: pending) }
    }
}
