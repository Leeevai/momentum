import Foundation

/// The temporary copies To-dos from Videos works on: what was added, the Photos picker's copies and
/// the sound taken out of a video, all named `momentum-import-…` in the temporary directory. The
/// sheet removes its own when it closes; what a crash or a force quit leaves is removed the next
/// time the sheet opens.
enum ImportScratch {
    private static let prefix = "momentum-import-"
    /// What builds before this naming called the Photos picker's copies.
    private static let olderPrefix = "momentum-picked-"

    /// A new place in the temporary directory for something the import makes: a folder or a file.
    static func newItem(named name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)\(name)-\(UUID().uuidString)")
    }

    /// Removes copies more than `age` seconds old, which no open sheet is still reading.
    static func removeLeftovers(olderThan age: TimeInterval = 24 * 60 * 60) {
        let manager = FileManager.default
        let cutoff = Date.now.addingTimeInterval(-age)
        let key = URLResourceKey.contentModificationDateKey
        guard let items = try? manager.contentsOfDirectory(at: manager.temporaryDirectory, includingPropertiesForKeys: [key]) else {
            return
        }
        for item in items where item.lastPathComponent.hasPrefix(prefix) || item.lastPathComponent.hasPrefix(olderPrefix) {
            let modified = (try? item.resourceValues(forKeys: [key]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? manager.removeItem(at: item) }
        }
    }
}
