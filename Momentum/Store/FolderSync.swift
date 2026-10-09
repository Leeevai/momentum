import AppKit
import MomentumCore
import Observation
import OSLog

/// Keeps this Mac's data in step with other devices through a folder the user picks, usually in
/// iCloud Drive. See `SyncFolder` for how the folder is laid out and why it can't conflict.
@MainActor
@Observable
final class FolderSync {
    struct Peer: Identifiable, Equatable {
        var id: String
        var name: String
        var platform: String
        var savedAt: Date
    }

    private(set) var folder: URL?
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var peers: [Peer] = []
    private(set) var isSyncing = false

    var isEnabled: Bool { folder != nil }

    @ObservationIgnored private weak var store: GoalStore?
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var lastWritten: AppData?
    @ObservationIgnored private var peerDates: [String: Date] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "dev.momentum.app", category: "Sync")

    private static let bookmarkKey = "syncFolderBookmark"
    private static let deviceKey = "syncDeviceID"

    /// A stable id for this Mac, made once.
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    init(store: GoalStore) {
        self.store = store
        restore()
    }

    // MARK: - Choosing the folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Sync Here"
        panel.message = "Choose a folder every device can reach, such as one in iCloud Drive. Use the same folder on each device."
        let iCloud = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: iCloud.path) { panel.directoryURL = iCloud }
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            open(url)
            syncNow()
        } catch {
            lastError = "Could not remember the folder: \(error.localizedDescription)"
        }
    }

    func stop() {
        close()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        peers = []
        lastSync = nil
        lastError = nil
    }

    private func restore() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            }
            open(url)
            syncNow()
        } catch {
            lastError = "The sync folder can't be found. Choose it again."
            logger.error("Could not resolve the sync folder: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func open(_ url: URL) {
        close()
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "Momentum isn't allowed to use that folder. Choose it again."
            return
        }
        folder = url
        lastError = nil
        watch(url)
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pull() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func close() {
        watcher?.cancel()
        watcher = nil
        pollTimer?.invalidate()
        pollTimer = nil
        writeTask?.cancel()
        folder?.stopAccessingSecurityScopedResource()
        folder = nil
        lastWritten = nil
        peerDates = [:]
    }

    private func watch(_ url: URL) {
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.pull() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        watcher = source
    }

    // MARK: - Syncing

    /// Reads every other device's copy now and writes this one's.
    func syncNow() {
        peerDates = [:]
        pull()
        scheduleWrite(after: .zero)
    }

    /// Called after every local change: writes this device's copy once changes settle.
    func localDataDidChange() {
        guard isEnabled else { return }
        scheduleWrite(after: .seconds(2))
    }

    private func scheduleWrite(after delay: Duration) {
        guard let folder else { return }
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let store = self.store else { return }
            let data = store.data
            guard data != self.lastWritten else { return }
            let envelope = SyncEnvelope(deviceID: Self.deviceID, deviceName: Host.current().localizedName ?? "Mac",
                                        platform: "macOS", savedAt: .now, data: data)
            let target = SyncFolder(url: folder, deviceID: Self.deviceID)
            do {
                try await Task.detached(priority: .utility) { try target.write(envelope) }.value
                self.lastWritten = data
                self.lastSync = .now
                self.lastError = nil
            } catch {
                self.lastError = "Could not write to the sync folder: \(error.localizedDescription)"
                self.logger.error("Sync write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Merges in any device's copy that changed since the last look.
    func pull() {
        guard let folder, !isSyncing else { return }
        let source = SyncFolder(url: folder, deviceID: Self.deviceID)
        let known = peerDates
        isSyncing = true
        Task { [weak self] in
            let (changed, dates, envelopes) = await Task.detached(priority: .utility) { () -> (Bool, [String: Date], [SyncEnvelope]) in
                let files = source.peerFiles()
                let dates = Dictionary(files.map { ($0.url.lastPathComponent, $0.modified) }, uniquingKeysWith: max)
                guard dates != known else { return (false, dates, []) }
                return (true, dates, source.readPeers())
            }.value
            guard let self else { return }
            self.isSyncing = false
            self.peerDates = dates
            guard changed else { return }
            self.peers = envelopes.map { Peer(id: $0.deviceID, name: $0.deviceName, platform: $0.platform, savedAt: $0.savedAt) }
            self.store?.merge(envelopes.map(\.data))
            self.lastSync = .now
        }
    }
}
