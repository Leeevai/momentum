import Foundation
import MomentumCore
import WidgetKit

/// The data file both the app and the widget extension use, in their shared app group container.
enum SharedStore {
    /// Set per build from `APP_GROUP_ID` in `Config/Shared.xcconfig`.
    static let appGroupID: String = Bundle.main.object(forInfoDictionaryKey: "MomentumAppGroupID") as? String ?? ""

    static let directoryURL: URL = {
        let container = appGroupID.isEmpty ? nil : FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        return (container ?? URL.applicationSupportDirectory).appendingPathComponent("Momentum", isDirectory: true)
    }()

    static let fileStore = FileStore(fileURL: directoryURL.appendingPathComponent("data.json"))

    static func load() -> AppData {
        fileStore.load()
    }

    /// Applies a change to the latest data on disk, saves it, and refreshes every widget.
    @discardableResult
    static func update(_ change: (inout AppData) -> Void) -> AppData {
        let data = fileStore.update(change)
        WidgetCenter.shared.reloadAllTimelines()
        return data
    }
}
