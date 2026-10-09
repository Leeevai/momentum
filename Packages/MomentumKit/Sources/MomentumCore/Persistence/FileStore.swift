import Foundation
import OSLog

/// Loads and saves `AppData` as JSON, coordinating access across processes.
///
/// The app and its widget extension (whose buttons run App Intents) both write the same file,
/// so every read-modify-write runs inside an `NSFileCoordinator` write.
public final class FileStore: Sendable {
    public let fileURL: URL
    private let logger = Logger(subsystem: "dev.momentum.core", category: "FileStore")

    /// Data together with the file's modification date at the moment it was read or written,
    /// taken inside the file coordinator so no other writer can slip in between the two.
    public struct Snapshot: Sendable {
        public var data: AppData
        public var modification: Date?

        public init(data: AppData, modification: Date?) {
            self.data = data
            self.modification = modification
        }
    }

    /// The result of a coordinated change.
    public struct Transform: Sendable {
        public var before: AppData
        public var after: AppData
        public var modification: Date?

        public init(before: AppData, after: AppData, modification: Date?) {
            self.before = before
            self.after = after
            self.modification = modification
        }
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> AppData {
        loadSnapshot().data
    }

    public func loadSnapshot() -> Snapshot {
        var snapshot = Snapshot(data: AppData(), modification: nil)
        coordinate(writing: false) { url in
            snapshot = Snapshot(data: self.read(url), modification: self.modificationDate())
        }
        return snapshot
    }

    /// Applies `change` to the latest data on disk and saves it.
    @discardableResult
    public func update(_ change: (inout AppData) -> Void) -> AppData {
        transform(change).after
    }

    /// Like `update`, returning the data as it was on disk before the change too, so the change
    /// can be described exactly (for undo), and the file's modification date after it.
    @discardableResult
    public func transform(_ change: (inout AppData) -> Void) -> Transform {
        var result = Transform(before: AppData(), after: AppData(), modification: nil)
        coordinate(writing: true) { url in
            let before = self.read(url)
            var after = before
            change(&after)
            if after != before { self.write(after, to: url) }
            result = Transform(before: before, after: after, modification: self.modificationDate())
        }
        return result
    }

    /// Replaces everything, keeping the previous file next to it as a backup.
    @discardableResult
    public func replace(with newData: AppData) -> Snapshot {
        var snapshot = Snapshot(data: newData, modification: nil)
        coordinate(writing: true) { url in
            self.backUp(url, reason: "before-import")
            self.write(newData, to: url)
            snapshot.modification = self.modificationDate()
        }
        return snapshot
    }

    // MARK: - Daily backups

    /// Where daily backups live: a Backups folder beside the data file.
    public var backupsDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    /// Copies today's data into `Backups/data-YYYY-MM-DD.json` if there is no copy for today yet,
    /// then keeps only the newest `keep` copies. Returns the backup written, if any.
    @discardableResult
    public func backUpDaily(keep: Int = 14, now: Date = .now, calendar: Calendar = .current) -> URL? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let name = String(format: "data-%04d-%02d-%02d.json", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let target = backupsDirectory.appendingPathComponent(name)
        var written: URL?
        do {
            try manager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            if !manager.fileExists(atPath: target.path) {
                coordinate(writing: false) { url in
                    do {
                        try manager.copyItem(at: url, to: target)
                        written = target
                    } catch {
                        self.logger.error("Daily backup failed: \(String(describing: error), privacy: .public)")
                    }
                }
            }
            let backups = try dailyBackups()
            for old in backups.dropFirst(max(1, keep)) {
                try manager.removeItem(at: old)
            }
        } catch {
            logger.error("Could not manage daily backups: \(String(describing: error), privacy: .public)")
        }
        return written
    }

    /// Daily backups, newest first.
    public func dailyBackups() throws -> [URL] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: backupsDirectory.path) else { return [] }
        return try manager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("data-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: - Encoding

    /// Compact by default, since the data file is rewritten on every change; `pretty` for exports.
    public static func encode(_ data: AppData, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
        return try encoder.encode(data)
    }

    /// When the data file last changed, to tell another process's write from one's own.
    public func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// Decodes any version of the data file, migrating older formats.
    public static func decode(_ bytes: Data) throws -> AppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let probe = try decoder.decode(VersionProbe.self, from: bytes)
        if probe.version == nil {
            return try decoder.decode(LegacyDataV1.self, from: bytes).migrated()
        }
        return try decoder.decode(AppData.self, from: bytes)
    }

    private struct VersionProbe: Decodable {
        var version: Int?
    }

    /// Whether the bytes are a pre-versioning (0.1) data file.
    static func isLegacy(_ bytes: Data) -> Bool {
        (try? JSONDecoder().decode(VersionProbe.self, from: bytes))?.version == nil
    }

    /// The first time an old-format file is read, keeps an untouched copy beside it,
    /// so the migration can always be undone by hand.
    private func keepLegacyCopy(of url: URL) {
        let copy = url.deletingLastPathComponent().appendingPathComponent("data.v1-backup.json")
        guard !FileManager.default.fileExists(atPath: copy.path) else { return }
        do {
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            logger.error("Could not keep a copy of the old data file: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - File access

    private func coordinate(writing: Bool, _ body: (URL) -> Void) {
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        if writing {
            coordinator.coordinate(writingItemAt: fileURL, options: [], error: &coordinationError, byAccessor: body)
        } else {
            coordinator.coordinate(readingItemAt: fileURL, options: [], error: &coordinationError, byAccessor: body)
        }
        if let coordinationError {
            logger.error("File coordination failed: \(coordinationError.localizedDescription, privacy: .public)")
        }
    }

    private func read(_ url: URL) -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppData() }
        do {
            let bytes = try Data(contentsOf: url)
            if Self.isLegacy(bytes) { keepLegacyCopy(of: url) }
            return try Self.decode(bytes)
        } catch {
            // Keep the unreadable file so the next save cannot destroy the history in it.
            logger.error("Could not read \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            backUp(url, reason: "unreadable")
            return AppData()
        }
    }

    private func write(_ data: AppData, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encode(data).write(to: url, options: .atomic)
        } catch {
            logger.error("Could not save \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func backUp(_ url: URL, reason: String) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension().appendingPathExtension("\(reason)-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: url, to: backup)
        } catch {
            logger.error("Could not back up \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
