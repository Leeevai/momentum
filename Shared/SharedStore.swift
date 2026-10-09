import Foundation
import MomentumCore
import OSLog
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
        transform(change).after
    }

    /// Like `update`, also returning the data before the change and the file's new date.
    @discardableResult
    static func transform(stamping: Bool = true, _ change: (inout AppData) -> Void) -> FileStore.Transform {
        let result = fileStore.transform(stamping: stamping, change)
        if result.before != result.after { reloadWidgets() }
        return result
    }

    // MARK: - Focus filter

    private static var focusFilterURL: URL { directoryURL.appendingPathComponent("focus-filter.json") }

    /// The categories the current macOS Focus asks Momentum to show, if any.
    static func loadFocusFilter() -> FocusFilter? {
        guard let bytes = try? Data(contentsOf: focusFilterURL) else { return nil }
        return try? JSONDecoder().decode(FocusFilter.self, from: bytes)
    }

    /// Sets or clears the Focus filter and refreshes the widgets.
    static func saveFocusFilter(_ filter: FocusFilter?) {
        do {
            if let filter, !filter.categories.isEmpty {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                try JSONEncoder().encode(filter).write(to: focusFilterURL, options: .atomic)
            } else if FileManager.default.fileExists(atPath: focusFilterURL.path) {
                try FileManager.default.removeItem(at: focusFilterURL)
            }
        } catch {
            logger.error("Could not save the Focus filter: \(error.localizedDescription, privacy: .public)")
        }
        reloadWidgets()
    }

    private static let logger = Logger(subsystem: "dev.momentum.shared", category: "SharedStore")

    /// Refreshes every widget and, on macOS 26, the Control Center focus control.
    static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
        #endif
    }
}
