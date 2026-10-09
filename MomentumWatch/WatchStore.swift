import Foundation
import MomentumCore
import Observation
import WatchConnectivity

/// The watch's side of the link to the iPhone: the latest snapshot of today, kept for when the
/// phone is out of reach, and the actions tapped here, sent back to be carried out.
@MainActor
@Observable
final class WatchStore: NSObject {
    private(set) var snapshot: WatchSnapshot
    /// An action is on its way to the phone.
    private(set) var isSending = false
    /// Actions waiting for the phone to come back in reach.
    private(set) var queuedActions = 0
    private(set) var isReachable = false

    @ObservationIgnored private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private static let storageKey = "snapshot"
    private typealias Key = WatchMessageKey

    override init() {
        snapshot = UserDefaults.standard.data(forKey: Self.storageKey).flatMap { try? WatchSnapshot(encoded: $0) } ?? WatchSnapshot()
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func item(_ id: UUID) -> WatchSnapshot.Item? { snapshot.item(id) }

    /// Asks the phone for a fresh snapshot, if it's in reach.
    func refresh() {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([Key.refresh: true]) { [weak self] reply in
            Task { @MainActor in self?.receive(reply) }
        } errorHandler: { _ in }
    }

    func perform(_ action: WatchAction) {
        guard let session, session.activationState == .activated, let encoded = try? action.encoded() else { return }
        let message: [String: Any] = [Key.action: encoded]
        guard session.isReachable else {
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
            Task { @MainActor in
                self?.isSending = false
                self?.queue(message, on: session)
            }
        }
    }

    /// Hands an action to the system to deliver when the phone is back, in order.
    private func queue(_ message: [String: Any], on session: WCSession) {
        session.transferUserInfo(message)
        queuedActions = session.outstandingUserInfoTransfers.count
    }

    fileprivate func receive(_ payload: [String: Any]) {
        guard let data = payload[Key.snapshot] as? Data, let snapshot = try? WatchSnapshot(encoded: data),
              snapshot.generatedAt >= self.snapshot.generatedAt else { return }
        self.snapshot = snapshot
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    fileprivate func update(reachable: Bool, pending: Int) {
        isReachable = reachable
        queuedActions = pending
        if reachable { refresh() }
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
