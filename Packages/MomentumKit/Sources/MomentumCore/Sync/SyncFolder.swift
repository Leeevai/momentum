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

    /// What reading one device's file gave.
    public enum PeerRead: Sendable {
        case read(SyncEnvelope)
        /// Not saved for `SyncState.peerLifetime`: left out, so a long-gone device can't bring
        /// back what was deleted since (see `SyncState.peerLifetime` for when it's still used).
        case stale(SyncEnvelope)
        /// Not readable now (still downloading, half written); worth trying again later.
        case unreadable
    }

    /// Reads one device's file.
    public func read(_ file: URL, now: Date = .now) -> PeerRead {
        var envelope: SyncEnvelope?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { source in
            do {
                envelope = try Self.decode(Data(contentsOf: source))
            } catch {
                Self.logger.error("Skipping \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        guard let envelope else { return .unreadable }
        return now.timeIntervalSince(envelope.savedAt) < SyncState.peerLifetime ? .read(envelope) : .stale(envelope)
    }

    /// Reads the other devices' copies, leaving out unreadable files and stale ones. With
    /// `startingFresh` (this device has no data yet), a folder holding only stale files is read
    /// anyway: with no fresher copy anywhere, there's no deletion they could undo.
    public func readPeers(now: Date = .now, startingFresh: Bool = false) -> [SyncEnvelope] {
        var fresh: [SyncEnvelope] = []
        var stale: [SyncEnvelope] = []
        for file in peerFiles() {
            switch read(file.url, now: now) {
            case .read(let envelope): fresh.append(envelope)
            case .stale(let envelope): stale.append(envelope)
            case .unreadable: break
            }
        }
        return startingFresh && fresh.isEmpty ? stale : fresh
    }

    public static func encode(_ envelope: SyncEnvelope) throws -> Data {
        try DateCoding.encoder().encode(envelope)
    }

    public static func decode(_ bytes: Data) throws -> SyncEnvelope {
        try DateCoding.decoder().decode(SyncEnvelope.self, from: bytes)
    }
}
