import Foundation
import OSLog

/// Loads and saves `AppData` as JSON, coordinating access across processes.
///
/// The app and its widget extension (whose buttons run App Intents) both write the same file,
/// so every read-modify-write runs inside an `NSFileCoordinator` write.
public final class FileStore: Sendable {
    public let fileURL: URL
    private let logger = Logger(subsystem: "dev.momentum.core", category: "FileStore")

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> AppData {
        var data = AppData()
        coordinate(writing: false) { url in data = self.read(url) }
        return data
    }

    /// Applies `change` to the latest data on disk and saves it.
    @discardableResult
    public func update(_ change: (inout AppData) -> Void) -> AppData {
        var data = AppData()
        coordinate(writing: true) { url in
            data = self.read(url)
            change(&data)
            self.write(data, to: url)
        }
        return data
    }

    /// Replaces everything, keeping the previous file next to it as a backup.
    public func replace(with newData: AppData) {
        coordinate(writing: true) { url in
            self.backUp(url, reason: "before-import")
            self.write(newData, to: url)
        }
    }

    // MARK: - Encoding

    public static func encode(_ data: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
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
