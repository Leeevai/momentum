import Foundation
import MomentumCore

/// Where the watch keeps the last snapshot from the iPhone: in the app group, so the watch face
/// complications read what the app shows.
enum WatchSnapshotStore {
    private static let key = "snapshot"

    private static var defaults: UserDefaults {
        let group = Bundle.main.object(forInfoDictionaryKey: "MomentumAppGroupID") as? String ?? ""
        return (group.isEmpty ? nil : UserDefaults(suiteName: group)) ?? .standard
    }

    static func load() -> WatchSnapshot? {
        defaults.data(forKey: key).flatMap { try? WatchSnapshot(encoded: $0) }
    }

    static func save(_ encoded: Data) {
        defaults.set(encoded, forKey: key)
    }
}
