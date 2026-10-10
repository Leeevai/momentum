import MomentumCore
import Observation
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Keeps this device's data in step with others through a folder the user picks, usually in
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
    @ObservationIgnored private var peersByID: [String: Peer] = [:]
    /// Devices whose files are in a newer data format, by file name: not merged until this
    /// device is updated.
    @ObservationIgnored private var newerPeers: [String: String] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "dev.momentum.app", category: "Sync")

    /// What Settings shows while a device's file is in a newer format: syncing with it waits for
    /// an update here.
    private var newerVersionNotice: String? {
        let names = Set(newerPeers.values).sorted()
        guard let first = names.first else { return nil }
        let devices = names.count == 1 ? "\(first) has" : "\(names.joined(separator: ", ")) have"
        return "\(devices) a newer version of Momentum. Update Momentum here to sync with \(names.count == 1 ? "it" : "them")."
    }

    private nonisolated static let bookmarkKey = "syncFolderBookmark"
    private nonisolated static let deviceKey = "syncDeviceID"

    /// Merges the other devices' copies straight into the data file, without the app's store:
    /// for intents (a Lock Screen button) that must not act on data older than the folder's.
    nonisolated static func catchUpFromFolder() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: bookmarkResolution, relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let envelopes = SyncFolder(url: url, deviceID: deviceID).readPeers()
        guard !envelopes.isEmpty else { return }
        let merged = SharedStore.transform(stamping: false) { data in
            for envelope in envelopes { data = SyncMerge.merge(data, envelope.data) }
        }
        // What the app settles after its own merges, settled here too, as this device's change.
        var probe = merged.after
        if probe.settleAfterMerge(from: merged.before) {
            SharedStore.transform { $0.settleAfterMerge(from: merged.before) }
        }
    }

    /// A stable id for this device, made once.
    nonisolated static var deviceID: String {
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

    /// Starts syncing through `url`, a folder the user picked, remembering it for next time.
    func useFolder(_ url: URL) {
        #if os(iOS)
        // A folder from the document picker is reachable only inside this window.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            let bookmark = try url.bookmarkData(options: Self.bookmarkCreation, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            open(url)
            syncNow()
        } catch {
            lastError = "Could not remember the folder: \(error.localizedDescription)"
        }
    }

    #if os(macOS)
    private nonisolated static let bookmarkCreation: URL.BookmarkCreationOptions = .withSecurityScope
    private nonisolated static let bookmarkResolution: URL.BookmarkResolutionOptions = .withSecurityScope
    private static let platform = "macOS"
    private static var deviceName: String { Host.current().localizedName ?? "Mac" }
    #else
    private nonisolated static let bookmarkCreation: URL.BookmarkCreationOptions = []
    private nonisolated static let bookmarkResolution: URL.BookmarkResolutionOptions = []
    private static let platform = "iOS"
    private static var deviceName: String { UIDevice.current.name }
    #endif

    #if os(macOS)
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
        useFolder(url)
    }
    #endif

    func stop() {
        close()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        peers = []
        peersByID = [:]
        lastSync = nil
        lastError = nil
    }

    private func restore() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: Self.bookmarkResolution, relativeTo: nil, bookmarkDataIsStale: &stale)
            open(url)
            // A stale bookmark can only be renewed while the folder is being accessed.
            if stale, folder != nil,
               let fresh = try? url.bookmarkData(options: Self.bookmarkCreation, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            }
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
        newerPeers = [:]
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
            let envelope = SyncEnvelope(deviceID: Self.deviceID, deviceName: Self.deviceName,
                                        platform: Self.platform, savedAt: .now, data: data)
            let target = SyncFolder(url: folder, deviceID: Self.deviceID)
            do {
                try await Task.detached(priority: .utility) { try target.write(envelope) }.value
                self.lastWritten = data
                self.lastSync = .now
                self.lastError = self.newerVersionNotice
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
        // With nothing here yet (a new device, a reinstall), a folder whose files are all stale is
        // read anyway: no fresher copy holds a deletion they could undo.
        let startingFresh = store.map { $0.data.goals.isEmpty && $0.data.entries.isEmpty && $0.data.sync.tombstones.isEmpty } ?? false
        isSyncing = true
        Task { [weak self] in
            // Only files changed since they were last read are read; a file that couldn't be
            // read (still downloading) keeps no date, so the next pass tries it again.
            let pass = await Task.detached(priority: .utility) { () -> PullPass in
                var pass = PullPass()
                var stale: [SyncEnvelope] = []
                for file in source.peerFiles() {
                    let name = file.url.lastPathComponent
                    if known[name] == file.modified {
                        pass.dates[name] = file.modified
                        continue
                    }
                    pass.read.insert(name)
                    switch source.read(file.url) {
                    case .read(let envelope):
                        pass.envelopes.append(envelope)
                        pass.dates[name] = file.modified
                    case .stale(let envelope):
                        stale.append(envelope)
                        pass.dates[name] = file.modified
                    case .newer(let deviceName):
                        // Not merged: this version would lose what it doesn't know. Not read
                        // again either until it changes.
                        pass.newer[name] = deviceName
                        pass.dates[name] = file.modified
                    case .unreadable:
                        break
                    }
                }
                if startingFresh && pass.envelopes.isEmpty && known.isEmpty { pass.envelopes = stale }
                return pass
            }.value
            guard let self else { return }
            self.isSyncing = false
            self.peerDates = pass.dates
            // Files read this time say whether they're newer; unchanged ones still say what they did.
            let previousNotice = self.newerVersionNotice
            self.newerPeers = self.newerPeers.filter { pass.dates[$0.key] != nil && !pass.read.contains($0.key) }
                .merging(pass.newer) { $1 }
            if self.newerVersionNotice != nil || self.lastError == previousNotice { self.lastError = self.newerVersionNotice }
            let envelopes = pass.envelopes
            guard !envelopes.isEmpty else { return }
            for envelope in envelopes {
                self.peersByID[envelope.deviceID] = Peer(id: envelope.deviceID, name: envelope.deviceName, platform: envelope.platform,
                                                         savedAt: envelope.savedAt)
            }
            self.peers = self.peersByID.values.sorted { $0.savedAt > $1.savedAt }
            self.store?.merge(envelopes.map(\.data))
            self.lastSync = .now
        }
    }

    /// What one look at the folder found.
    private struct PullPass: Sendable {
        /// Every peer file's date as last read, by file name.
        var dates: [String: Date] = [:]
        /// Files read this time, rather than skipped as unchanged.
        var read: Set<String> = []
        /// Devices whose files are in a newer data format, by file name.
        var newer: [String: String] = [:]
        var envelopes: [SyncEnvelope] = []
    }
}
