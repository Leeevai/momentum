import Foundation
import MomentumCore

/// Where the app's data lives: the shared app-group file, or memory for previews and screenshots.
protocol DataPersistence: AnyObject {
    func load() -> AppData
    func update(_ change: (inout AppData) -> Void) -> AppData
    func replace(with data: AppData)
    /// The folder to watch for changes made by other processes (the widgets), if any.
    var watchedDirectory: URL? { get }
}

final class SharedFilePersistence: DataPersistence {
    func load() -> AppData { SharedStore.load() }

    func update(_ change: (inout AppData) -> Void) -> AppData { SharedStore.update(change) }

    func replace(with data: AppData) {
        SharedStore.fileStore.replace(with: data)
        _ = SharedStore.update { _ in }
    }

    var watchedDirectory: URL? { SharedStore.directoryURL }
}

final class InMemoryPersistence: DataPersistence {
    private var data: AppData

    init(_ data: AppData) { self.data = data }

    func load() -> AppData { data }

    func update(_ change: (inout AppData) -> Void) -> AppData {
        change(&data)
        return data
    }

    func replace(with data: AppData) { self.data = data }

    var watchedDirectory: URL? { nil }
}
