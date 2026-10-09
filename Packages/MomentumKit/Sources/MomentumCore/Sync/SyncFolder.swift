import Foundation
import OSLog

/// One device's copy of the data, as written to a sync folder.
public struct SyncEnvelope: Codable, Sendable {
    public var deviceID: String
    public var deviceName: String
    /// "macOS" or "iOS".
    public var platform: String
    public var savedAt: Date
    public var data: AppData

    public init(deviceID: String, deviceName: String, platform: String, savedAt: Date, data: AppData) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.savedAt = savedAt
        self.data = data
    }
}

/// Syncs through any folder every device can reach: iCloud Drive, Dropbox, a network share.
///
/// Each device writes only its own file, `<device id>.momentum-sync`, so no two devices ever
/// write the same file and no sync service has a conflict to resolve. Each device reads the
/// others' files and merges them into its data with `SyncMerge`, then writes the result as its
/// own file; since the merge converges, every device ends up with the same data.
public struct SyncFolder: Sendable {
    public let url: URL
    public let deviceID: String

    public static let fileExtension = "momentum-sync"
    private static let logger = Logger(subsystem: "dev.momentum.core", category: "SyncFolder")

    public init(url: URL, deviceID: String) {
        self.url = url
        self.deviceID = deviceID
    }

    public var ownFileURL: URL {
        url.appendingPathComponent("\(deviceID).\(Self.fileExtension)")
    }

    /// Writes this device's copy, atomically and through a file coordinator.
    public func write(_ envelope: SyncEnvelope) throws {
        let bytes = try Self.encode(envelope)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: ownFileURL, options: .forReplacing, error: &coordinationError) { target in
            do {
                try bytes.write(to: target, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    /// The other devices' files with their modification dates, asking the sync service to
    /// download any it has only as a placeholder.
    public func peerFiles() -> [(url: URL, modified: Date)] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey],
                                                           options: []) else { return [] }
        var files: [(URL, Date)] = []
        for file in names {
            let name = file.lastPathComponent
            // iCloud keeps files not downloaded yet as hidden ".<name>.icloud" placeholders.
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = String(name.dropFirst().dropLast(".icloud".count))
                if real.hasSuffix(".\(Self.fileExtension)") && !real.hasPrefix(deviceID) {
                    try? manager.startDownloadingUbiquitousItem(at: file)
                }
                continue
            }
            guard file.pathExtension == Self.fileExtension, file.deletingPathExtension().lastPathComponent != deviceID else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            files.append((file, modified))
        }
        return files.sorted { $0.0.lastPathComponent < $1.0.lastPathComponent }
    }

    /// Reads the other devices' copies. Unreadable files are skipped and logged: a half-synced
    /// file is read again on the next pass.
    public func readPeers() -> [SyncEnvelope] {
        peerFiles().compactMap { file in
            var envelope: SyncEnvelope?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: file.url, options: [], error: &coordinationError) { source in
                do {
                    envelope = try Self.decode(Data(contentsOf: source))
                } catch {
                    Self.logger.error("Skipping \(file.url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            return envelope
        }
    }

    public static func encode(_ envelope: SyncEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    public static func decode(_ bytes: Data) throws -> SyncEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SyncEnvelope.self, from: bytes)
    }
}
