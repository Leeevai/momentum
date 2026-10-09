import Foundation
import MomentumCore
import WidgetKit

/// Where the app's data lives: the shared app-group file, or memory for previews and screenshots.
protocol DataPersistence: AnyObject {
    func load() -> AppData
    /// Applies a change to the latest stored data; returns the data before and after.
    func update(_ change: (inout AppData) -> Void) -> (before: AppData, after: AppData)
    func replace(with data: AppData)
    /// The folder to watch for changes made by other processes (the widgets), if any.
    var watchedDirectory: URL? { get }
    /// Keeps a dated copy of the data, at most once a day.
    func backUpDaily()
    /// Daily backups, newest first.
    func dailyBackups() -> [URL]
    /// When the stored data last changed.
    func modificationDate() -> Date?
    /// The modification date this app's latest write produced, to recognize its own saves.
    func lastWriteModification() -> Date?
}

final class SharedFilePersistence: DataPersistence {
    func load() -> AppData { SharedStore.load() }

    func update(_ change: (inout AppData) -> Void) -> (before: AppData, after: AppData) { SharedStore.transform(change) }

    func replace(with data: AppData) {
        SharedStore.fileStore.replace(with: data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    var watchedDirectory: URL? { SharedStore.directoryURL }

    func backUpDaily() { SharedStore.fileStore.backUpDaily() }

    func dailyBackups() -> [URL] { (try? SharedStore.fileStore.dailyBackups()) ?? [] }

    func modificationDate() -> Date? { SharedStore.fileStore.modificationDate() }

    func lastWriteModification() -> Date? { SharedStore.fileStore.lastWriteModification }
}

final class InMemoryPersistence: DataPersistence {
    private var data: AppData

    init(_ data: AppData) { self.data = data }

    func load() -> AppData { data }

    func update(_ change: (inout AppData) -> Void) -> (before: AppData, after: AppData) {
        let before = data
        change(&data)
        return (before, data)
    }

    func replace(with data: AppData) { self.data = data }

    var watchedDirectory: URL? { nil }

    func backUpDaily() {}

    func dailyBackups() -> [URL] { [] }

    func modificationDate() -> Date? { nil }

    func lastWriteModification() -> Date? { nil }
}
