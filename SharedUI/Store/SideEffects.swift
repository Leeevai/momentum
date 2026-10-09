import MomentumCore
import Observation
import OSLog
import UserNotifications
#if os(macOS)
import AppKit
import ServiceManagement
#else
import UIKit
#endif

/// Everything that happens outside the data file when data changes: notifications, opening a
/// goal's links when a session starts, and the end-of-session sound.
@MainActor
final class SideEffects {
    let notifications: NotificationScheduler
    let focusSound = FocusSoundPlayer()
    private let isEnabled: Bool
    private var lastSessionStart: Date?
    private var replanTask: Task<Void, Never>?
    private var downloadingCovers: Set<UUID> = []

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
        self.notifications = NotificationScheduler()
    }

    func attach(to store: GoalStore) {
        notifications.store = store
    }

    func start(with data: AppData, engine: ProgressEngine) {
        lastSessionStart = data.session?.startedAt
        guard isEnabled else { return }
        MomentumShortcuts.updateAppShortcutParameters()
        notifications.activate()
        scheduleReplan(engine: engine)
        notifications.syncSessionEnd(data.session, goal: data.session.flatMap { engine.goal($0.goalID) }, pomodoro: data.preferences.pomodoro)
        notifications.syncRestEnd(data.rest, goal: data.rest.flatMap { engine.goal($0.goalID) })
        syncFocusSound(data)
        syncLiveActivity(data)
        cacheCovers(data)
    }

    func dataDidChange(from old: AppData, to new: AppData, engine: ProgressEngine) {
        guard isEnabled else { return }
        if let session = new.session, session.startedAt != lastSessionStart {
            lastSessionStart = session.startedAt
            // On a Mac the goal's links open beside the timer; on iPhone that would leave the app.
            #if os(macOS)
            if let goal = engine.goal(session.goalID) { LinkOpener.openFocusLinks(of: goal) }
            #endif
        } else if new.session == nil {
            lastSessionStart = nil
        }
        if old.goals.map(\.name) != new.goals.map(\.name) {
            // Siri and Spotlight phrases name goals ("Focus on Deep work"); keep them current.
            MomentumShortcuts.updateAppShortcutParameters()
        }
        if old.session != new.session || old.preferences.pomodoro != new.preferences.pomodoro {
            notifications.syncSessionEnd(new.session, goal: new.session.flatMap { engine.goal($0.goalID) }, pomodoro: new.preferences.pomodoro)
        }
        if old.rest != new.rest {
            notifications.syncRestEnd(new.rest, goal: new.rest.flatMap { engine.goal($0.goalID) })
        }
        if old.session != new.session || old.rest != new.rest || old.goals != new.goals {
            syncLiveActivity(new)
        }
        if old.session?.isRunning != new.session?.isRunning || old.preferences != new.preferences {
            syncFocusSound(new)
        }
        cacheCovers(new)
        scheduleReplan(engine: engine)
    }

    /// Downloads covers the widgets don't have yet, and removes ones whose books are gone.
    private func cacheCovers(_ data: AppData) {
        let books = data.goals.flatMap(\.books)
        let missing = books.filter { $0.coverURL != nil && !CoverCache.hasCover(for: $0) && !downloadingCovers.contains($0.id) }
        for book in missing {
            guard let url = book.coverURL else { continue }
            downloadingCovers.insert(book.id)
            Task { [weak self] in
                defer { self?.downloadingCovers.remove(book.id) }
                do {
                    let (bytes, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200, PlatformImage(data: bytes) != nil else { return }
                    try FileManager.default.createDirectory(at: CoverCache.directoryURL, withIntermediateDirectories: true)
                    try bytes.write(to: CoverCache.fileURL(for: book.id), options: .atomic)
                    SharedStore.reloadWidgets()
                } catch {
                    Logger(subsystem: "dev.momentum.app", category: "Covers")
                        .error("Could not cache a cover: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        let known = Set(books.map { "\($0.id.uuidString).jpg" })
        if let files = try? FileManager.default.contentsOfDirectory(atPath: CoverCache.directoryURL.path) {
            for file in files where !known.contains(file) {
                try? FileManager.default.removeItem(at: CoverCache.directoryURL.appendingPathComponent(file))
            }
        }
    }

    /// The focus timer on the Lock Screen and in the Dynamic Island (iPhone). Only an app in
    /// the foreground can start one, so the app also calls this when it becomes active.
    func syncLiveActivity(_ data: AppData) {
        guard isEnabled else { return }
        #if os(iOS)
        Task { await FocusActivityController.sync(with: data) }
        #endif
    }

    /// Plays the chosen sound while a session runs; fades it out on pause or stop.
    private func syncFocusSound(_ data: AppData) {
        if data.session?.isRunning == true {
            focusSound.play(data.preferences.focusSound, volume: data.preferences.focusSoundVolume)
        } else {
            focusSound.stop()
        }
    }

    func play(_ sound: AppSound, preferences: Preferences) {
        guard isEnabled, preferences.playsSounds else { return }
        #if os(macOS)
        let name = switch sound {
        case .goalCompleted: "Glass"
        case .blockCompleted: "Hero"
        case .blockStarted: "Purr"
        case .award: "Funk"
        }
        NSSound(named: name)?.play()
        #else
        switch sound {
        case .goalCompleted, .award: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .blockCompleted: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .blockStarted: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        #endif
    }

    func dayDidChange(engine: ProgressEngine) {
        guard isEnabled else { return }
        scheduleReplan(engine: engine)
    }

    /// Replans reminders once changes settle, rather than on every keystroke-sized edit.
    private func scheduleReplan(engine: ProgressEngine) {
        replanTask?.cancel()
        replanTask = Task { [notifications] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await notifications.replanReminders(engine: engine)
        }
    }
}

// MARK: - Notifications

@MainActor
@Observable
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @ObservationIgnored weak var store: GoalStore?

    private var center: UNUserNotificationCenter { .current() }
    @ObservationIgnored private let logger = Logger(subsystem: "dev.momentum.app", category: "Notifications")

    static let sessionEndID = "session.end"
    private enum Category {
        static let reminder = "goal.reminder"
        static let sessionEnd = "session.end"
        static let restEnd = "rest.end"
    }
    private enum Action {
        static let start = "start"
        static let quickAdd = "quick-add"
        static let stop = "stop"
        static let extend = "extend"
        static let nextBlock = "next-block"
    }

    func activate() {
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.reminder, actions: [
                UNNotificationAction(identifier: Action.start, title: "Start now", options: [.foreground]),
                UNNotificationAction(identifier: Action.quickAdd, title: "Log progress"),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.sessionEnd, actions: [
                UNNotificationAction(identifier: Action.stop, title: "Stop and save"),
                UNNotificationAction(identifier: Action.extend, title: "5 more minutes"),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.restEnd, actions: [
                UNNotificationAction(identifier: Action.nextBlock, title: "Start next block"),
            ], intentIdentifiers: []),
        ])
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Asks for permission the first time something needs it.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            return granted
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func replanReminders(engine: ProgressEngine) async {
        let planned = ReminderPlanner.plan(engine, now: .now)
        if !planned.isEmpty && authorization == .notDetermined {
            await requestAuthorization()
        }
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        guard authorization == .authorized || authorization == .provisional else { return }
        for reminder in planned {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.subtitle = reminder.subtitle
            content.body = reminder.body
            content.sound = .default
            content.categoryIdentifier = Category.reminder
            content.userInfo = ["goal": reminder.goalID.uuidString]
            content.threadIdentifier = reminder.goalID.uuidString
            let parts = engine.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            do {
                try await center.add(request)
            } catch {
                logger.error("Could not schedule \(reminder.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Keeps the "time's up" notification in step with the session: scheduled while a planned
    /// session runs, removed when it pauses or stops.
    func syncSessionEnd(_ session: FocusSession?, goal: Goal?, pomodoro: PomodoroSettings) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.sessionEndID])
        guard let session, let goal, let end = session.plannedEnd, end > .now else { return }
        Task {
            if authorization == .notDetermined { await requestAuthorization() }
            guard authorization == .authorized || authorization == .provisional else { return }
            let content = UNMutableNotificationContent()
            let length = Formatting.duration(session.plannedDuration ?? 0)
            if pomodoro.isEnabled {
                let isLong = session.block >= pomodoro.blocksPerCycle
                let minutes = isLong ? pomodoro.longBreakMinutes : pomodoro.shortBreakMinutes
                content.title = "Block \(session.block) done"
                content.body = "\(length) of \(goal.name) saved. Enjoy a \(minutes)-minute \(isLong ? "long " : "")break."
            } else {
                content.title = "Time's up"
                content.body = "\(length) of \(goal.name) done. Take a breather."
            }
            content.subtitle = goal.name
            content.sound = .default
            content.categoryIdentifier = pomodoro.isEnabled ? "" : Category.sessionEnd
            content.userInfo = ["goal": goal.id.uuidString]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: Self.sessionEndID, content: content, trigger: trigger))
            } catch {
                logger.error("Could not schedule the session end: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    static let restEndID = "rest.end"

    /// "Break's over" when a Pomodoro break ends, unless the next block starts by itself.
    func syncRestEnd(_ rest: RestPeriod?, goal: Goal?) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.restEndID])
        guard let rest, let goal, rest.end > .now, store?.data.preferences.pomodoro.autoStartsNextBlock != true else { return }
        Task {
            guard authorization == .authorized || authorization == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Break's over"
            content.subtitle = goal.name
            content.body = "Ready for block \(rest.nextBlock)?"
            content.sound = .default
            content.categoryIdentifier = Category.restEnd
            content.userInfo = ["goal": goal.id.uuidString]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, rest.end.timeIntervalSinceNow), repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: Self.restEndID, content: content, trigger: trigger))
            } catch {
                logger.error("Could not schedule the break end: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Brings the app forward after a notification action; on iPhone, tapping already did.
    private static func activateApp() {
        #if os(macOS)
        NSApp.activate()
        #endif
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let goalID = (response.notification.request.content.userInfo["goal"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        await MainActor.run {
            guard let store = self.store else { return }
            switch action {
            case Action.start:
                if let goalID, let goal = store.goal(goalID) {
                    if goal.kind == .time { store.toggleFocus(goal) } else { store.select(goalID) }
                    Self.activateApp()
                }
            case Action.quickAdd:
                if let goalID, let goal = store.goal(goalID) { store.quickAdd(goal) }
            case Action.stop:
                store.stopFocus()
            case Action.extend:
                store.extendFocus()
                store.effects.notifications.syncSessionEnd(store.data.session, goal: goalID.flatMap(store.goal), pomodoro: store.data.preferences.pomodoro)
            case Action.nextBlock:
                store.startNextBlock()
            default:
                if let goalID { store.select(goalID) }
                Self.activateApp()
            }
        }
    }
}

// MARK: - Links

#if os(macOS)

enum LinkOpener {
    private static let logger = Logger(subsystem: "dev.momentum.app", category: "Links")

    @MainActor
    @discardableResult
    static func open(_ link: GoalLink) -> Bool {
        if let bookmark = link.bookmark {
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale)
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return NSWorkspace.shared.open(url)
            } catch {
                logger.error("Could not resolve the bookmark for \(link.displayTitle, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return NSWorkspace.shared.open(link.url)
    }

    @MainActor
    static func openFocusLinks(of goal: Goal) {
        for link in goal.links where link.opensWithFocus { open(link) }
    }

    /// A bookmark that lets the sandboxed app reopen a file the user picked.
    static func bookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            logger.error("Could not bookmark \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The icon of whatever opens the link: the browser, Notion, Xcode, or the file itself.
    @MainActor
    static func icon(for link: GoalLink) -> NSImage {
        let key = link.url.isFileURL ? link.url.path : (link.url.scheme ?? "") + "|" + (link.url.host() ?? "")
        if let cached = iconCache[key] { return cached }
        let image: NSImage
        if link.url.isFileURL {
            image = NSWorkspace.shared.icon(forFile: link.url.path)
        } else if let app = NSWorkspace.shared.urlForApplication(toOpen: link.url) {
            image = NSWorkspace.shared.icon(forFile: app.path)
        } else {
            image = NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[key] = image
        return image
    }

    @MainActor private static var iconCache: [String: NSImage] = [:]
}
#else
enum LinkOpener {
    @MainActor
    @discardableResult
    static func open(_ link: GoalLink) -> Bool {
        UIApplication.shared.open(link.url)
        return true
    }
}
#endif

// MARK: - Login item

#if os(macOS)
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
#endif
