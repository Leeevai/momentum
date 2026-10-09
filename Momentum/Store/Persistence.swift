import Foundation
import MomentumCore

/// Where the app's data lives: the shared app-group file, or memory for previews and screenshots.
protocol DataPersistence: AnyObject {
    /// The stored data and the file's date as it was read.
    func load() -> FileStore.Snapshot
    /// Applies a change to the latest stored data; returns the data before and after, and the
    /// file's date after the write, read inside the same coordinated access.
    func update(_ change: (inout AppData) -> Void) -> FileStore.Transform
    func replace(with data: AppData) -> FileStore.Snapshot
    /// The folder to watch for changes made by other processes (the widgets), if any.
    var watchedDirectory: URL? { get }
    /// Keeps a dated copy of the data, at most once a day.
    func backUpDaily()
    /// Daily backups, newest first.
    func dailyBackups() -> [URL]
    /// When the stored data last changed.
    func modificationDate() -> Date?
}

final class SharedFilePersistence: DataPersistence {
    func load() -> FileStore.Snapshot { SharedStore.fileStore.loadSnapshot() }

    func update(_ change: (inout AppData) -> Void) -> FileStore.Transform { SharedStore.transform(change) }

    func replace(with data: AppData) -> FileStore.Snapshot {
        let snapshot = SharedStore.fileStore.replace(with: data)
        SharedStore.reloadWidgets()
        return snapshot
    }

    var watchedDirectory: URL? { SharedStore.directoryURL }

    func backUpDaily() { SharedStore.fileStore.backUpDaily() }

    func dailyBackups() -> [URL] { (try? SharedStore.fileStore.dailyBackups()) ?? [] }

    func modificationDate() -> Date? { SharedStore.fileStore.modificationDate() }
}

final class InMemoryPersistence: DataPersistence {
    private var data: AppData

    init(_ data: AppData) { self.data = data }

    func load() -> FileStore.Snapshot { FileStore.Snapshot(data: data, modification: nil) }

    func update(_ change: (inout AppData) -> Void) -> FileStore.Transform {
        let before = data
        change(&data)
        return FileStore.Transform(before: before, after: data, modification: nil)
    }

    func replace(with data: AppData) -> FileStore.Snapshot {
        self.data = data
        return FileStore.Snapshot(data: data, modification: nil)
    }

    var watchedDirectory: URL? { nil }

    func backUpDaily() {}

    func dailyBackups() -> [URL] { [] }

    func modificationDate() -> Date? { nil }
}
