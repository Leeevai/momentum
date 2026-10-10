import Foundation
import OSLog

/// Loads and saves `AppData` as JSON, coordinating access across processes.
///
/// The app and its widget extension (whose buttons run App Intents) both write the same file,
/// so every read-modify-write runs inside an `NSFileCoordinator` write.
public final class FileStore: Sendable {
    public let fileURL: URL
    private let logger = Logger(subsystem: "dev.momentum.core", category: "FileStore")
    /// The data as last read or written, with the file date it belongs to. A file whose date
    /// hasn't moved since is not decoded again: with years of history that's the slow part of a save.
    private let cache = ReadCache()

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
            snapshot = Snapshot(data: self.read(url).data, modification: self.modificationDate())
        }
        return snapshot
    }

    /// Whether the data file exists but couldn't be read (damaged, or written by a newer
    /// version). Nothing is saved over it then, except an import or a restored copy.
    public var isUnreadable: Bool {
        cache.isUnreadable(modification: modificationDate())
    }

    /// Applies `change` to the latest data on disk and saves it.
    @discardableResult
    public func update(_ change: (inout AppData) -> Void) -> AppData {
        transform(change).after
    }

    /// Like `update`, returning the data as it was on disk before the change too, so the change
    /// can be described exactly (for undo), and the file's modification date after it.
    ///
    /// Changed records are stamped for syncing, except when `stamping` is off: a merge from
    /// another device already carries the stamps of when each change was really made.
    @discardableResult
    public func transform(stamping: Bool = true, _ change: (inout AppData) -> Void) -> Transform {
        var result = Transform(before: AppData(), after: AppData(), modification: nil)
        coordinate(writing: true) { url in
            let (before, readable) = self.read(url)
            guard readable else {
                // Saving the change would replace history this version can't read with almost
                // nothing: refuse, and leave the file as it is.
                self.logger.error("Not saving: \(url.path, privacy: .public) can't be read")
                result = Transform(before: before, after: before, modification: self.modificationDate())
                return
            }
            var after = before
            change(&after)
            if after != before {
                if stamping { SyncStamper.stamp(&after, from: before, at: .now) }
                self.write(after, to: url)
            }
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
            // Stamped against what it replaces, so other devices take the import over their copy.
            // It keeps this device's record of changes and deletions rather than the backup's
            // older one: that is how a restored entry is known to have been deleted since, and is
            // stamped so the deletion doesn't win again at the next sync.
            let current = self.read(url).data
            var stamped = newData
            stamped.sync = current.sync
            SyncStamper.stamp(&stamped, from: current, at: .now)
            self.write(stamped, to: url)
            snapshot = Snapshot(data: stamped, modification: self.modificationDate())
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
        // Gregorian whatever the device's calendar, so names sort by date.
        let name = "data-\(DayID(now, calendar: calendar)).json"
        let target = backupsDirectory.appendingPathComponent(name)
        var written: URL?
        do {
            try manager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            if !manager.fileExists(atPath: target.path) {
                coordinate(writing: false) { url in
                    // A file that can't be read isn't a day's copy: two weeks of them would push
                    // out every good copy, the ones a restore needs. It's kept aside once anyway.
                    guard self.read(url).isReadable else {
                        self.logger.error("No daily backup: \(url.path, privacy: .public) can't be read")
                        return
                    }
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
        // By the file's date, not its name: names from before 2.0 followed the device's calendar,
        // and a Buddhist-calendar year (2569) would sort above every new one.
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return try manager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("data-") && $0.pathExtension == "json" }
            .map { ($0, modified($0)) }
            .sorted { ($0.1, $0.0.lastPathComponent) > ($1.1, $1.0.lastPathComponent) }
            .map(\.0)
    }

    // MARK: - Encoding

    /// Compact by default, since the data file is rewritten on every change; `pretty` for exports.
    public static func encode(_ data: AppData, pretty: Bool = false) throws -> Data {
        try DateCoding.encoder(pretty: pretty).encode(data)
    }

    /// When the data file last changed, to tell another process's write from one's own.
    public func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// Decodes any version of the data file, migrating older formats.
    public static func decode(_ bytes: Data) throws -> AppData {
        let decoder = DateCoding.decoder()
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

    /// The data in the file, and whether it could be read: a missing file is empty data, read
    /// fine; a file that fails to decode is empty data that mustn't be saved over it.
    private func read(_ url: URL) -> (data: AppData, isReadable: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (AppData(), true) }
        let modification = modificationDate()
        if let cached = cache.data(for: modification) { return (cached, true) }
        do {
            let bytes = try Data(contentsOf: url)
            if Self.isLegacy(bytes) { keepLegacyCopy(of: url) }
            let data = try Self.decode(bytes)
            cache.store(data, modification: modification)
            return (data, true)
        } catch {
            // Keep a copy of the unreadable file, once per version of it.
            logger.error("Could not read \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            if cache.markUnreadable(modification: modification) { backUp(url, reason: "unreadable") }
            return (AppData(), false)
        }
    }

    private func write(_ data: AppData, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encode(data).write(to: url, options: .atomic)
            cache.store(data, modification: modificationDate())
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

/// The last data a `FileStore` read or wrote, keyed by the file's modification date, and the
/// date of a version that couldn't be read.
private final class ReadCache: @unchecked Sendable {
    private let lock = NSLock()
    private var modification: Date?
    private var data: AppData?
    private var unreadable: Date?

    /// Records that the file at `modification` couldn't be read; false if that was known.
    func markUnreadable(modification: Date?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard modification == nil || unreadable != modification else { return false }
        unreadable = modification
        return true
    }

    func isUnreadable(modification: Date?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return modification != nil && unreadable == modification
    }

    func data(for modification: Date?) -> AppData? {
        lock.lock()
        defer { lock.unlock() }
        guard let modification, modification == self.modification else { return nil }
        return data
    }

    func store(_ data: AppData, modification: Date?) {
        lock.lock()
        defer { lock.unlock() }
        self.modification = modification
        self.data = modification == nil ? nil : data
    }
}
