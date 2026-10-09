import MomentumCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Observation
import OSLog

enum Route: Hashable {
    case today
    case journal
    case insights
    case awards
    case goal(UUID)
}

enum SheetRoute: Identifiable {
    case quickActions
    case newGoal
    case editGoal(Goal)
    case log(goalID: UUID, entry: LogEntry? = nil, day: Date? = nil)
    case link(goalID: UUID, link: GoalLink?)
    case book(goalID: UUID, book: Book?)
    case share(Goal)
    /// The morning plan, or the evening reflection, for a day.
    case plan(DayID)
    case reflect(DayID)

    var id: String {
        switch self {
        case .quickActions: "quick-actions"
        case .newGoal: "new"
        case .editGoal(let goal): "edit-\(goal.id)"
        case .log(let id, let entry, let day): "log-\(id)-\(entry?.id.uuidString ?? "new")-\(day?.timeIntervalSince1970 ?? 0)"
        case .link(let goal, let link): "link-\(goal)-\(link?.id.uuidString ?? "new")"
        case .book(let goal, let book): "book-\(goal)-\(book?.id.uuidString ?? "new")"
        case .share(let goal): "share-\(goal.id)"
        case .plan(let day): "plan-\(day)"
        case .reflect(let day): "reflect-\(day)"
        }
    }
}

/// A goal that just reached its target, for the celebration overlay.
struct Celebration: Identifiable, Equatable {
    let id = UUID()
    let goal: Goal
    /// The goal stacked after it, offered next.
    var next: Goal?
}

/// A brief banner at the top of the window.
struct Toast: Identifiable, Equatable {
    enum Kind: Equatable {
        case achievement(Achievement)
        /// Several earned at once, as on first launch after an update.
        case achievements(Int)
        case message(title: String, detail: String, symbol: String)
    }

    let id = UUID()
    let kind: Kind
}

/// The app's single source of truth.
///
/// Every change goes through `perform`, which writes the shared data file (so the widgets see
/// it), rebuilds the progress engine, registers undo, and runs side effects. Changes the widgets
/// make are picked up by watching the data folder.
@MainActor
@Observable
final class GoalStore {
    private(set) var data: AppData
    private(set) var engine: ProgressEngine
    /// Refreshed on every change and when the day rolls over; live counters use `TimelineView`.
    private(set) var now = Date()
    var route: Route? = .today
    var sheet: SheetRoute?
    var celebration: Celebration?
    var toast: Toast?
    /// Coach tips dismissed today.
    private(set) var dismissedTips: Set<String> = []
    /// A goal awaiting delete confirmation.
    var confirmingDelete: Goal?
    /// Text typed in the sidebar search field.
    var searchText = ""
    /// The categories the current macOS Focus asks for, if a Focus filter is on.
    private(set) var focusFilter: FocusFilter?
    /// A Focus filter the user chose to see past ("Show all") until it changes.
    var ignoredFocusFilter: FocusFilter?

    /// The main window's undo manager, attached by the root view.
    @ObservationIgnored weak var undoManager: UndoManager?

    @ObservationIgnored let effects: SideEffects
    /// Syncing through a shared folder; nil for previews.
    @ObservationIgnored private(set) var sync: FolderSync?
    @ObservationIgnored private let persistence: DataPersistence
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var dayTimer: Timer?
    @ObservationIgnored private var pomodoroTimer: Timer?
    @ObservationIgnored private var toastQueue: [Toast] = []
    @ObservationIgnored private var tipsCache: (key: String, tips: [CoachTip])?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// The data file's modification date as of the last read or write by this app.
    @ObservationIgnored private var knownModification: Date?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.momentum.app", category: "GoalStore")

    init(persistence: DataPersistence = SharedFilePersistence(), effects: SideEffects? = nil) {
        let snapshot = persistence.load()
        let initial = snapshot.data
        self.persistence = persistence
        self.knownModification = snapshot.modification
        self.data = initial
        self.engine = ProgressEngine(data: initial)
        self.effects = effects ?? SideEffects()
        self.focusFilter = persistence.watchedDirectory == nil ? nil : SharedStore.loadFocusFilter()
        self.effects.attach(to: self)
        self.effects.start(with: initial, engine: engine)
        dismissedTips = Self.loadDismissedTips(on: .now)
        watchForExternalChanges()
        startDayTimer()
        advancePomodoro()
        schedulePomodoro()
        recordAchievements()
        if persistence.watchedDirectory != nil { sync = FolderSync(store: self) }
        persistence.backUpDaily()
        #if os(macOS)
        let becameActive = NSApplication.didBecomeActiveNotification
        #else
        let becameActive = UIApplication.didBecomeActiveNotification
        #endif
        observers.append(NotificationCenter.default.addObserver(forName: becameActive, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reload()
                self?.sync?.pull()
            }
        })
    }

    /// An in-memory store with demo data, for previews and screenshots.
    static func preview(_ data: AppData = .demo()) -> GoalStore {
        GoalStore(persistence: InMemoryPersistence(data), effects: SideEffects(isEnabled: false))
    }

    // MARK: - Changing data

    /// Applies a change, saves it, and registers it for undo under `undoName`.
    ///
    /// Undo reverses only what this change touched (see `DataPatch`), so anything changed since,
    /// by a widget, Shortcuts or another action, survives it.
    func perform(_ undoName: String? = nil, _ change: (inout AppData) -> Void) {
        let result = persistence.update(change)
        knownModification = result.modification
        if let undoName {
            let patch = DataPatch(from: result.before, to: result.after)
            if !patch.isEmpty { registerUndo(patch, name: undoName) }
        }
        apply(result.after, userInitiated: true)
    }

    /// Picks up changes made by the widgets or Shortcuts. The folder watcher also fires for the
    /// app's own saves; those leave the file as the app last saw it, so they are skipped.
    func reload() {
        refreshFocusFilter()
        // A cheap check first; the date that counts is the one read with the data.
        if let modification = persistence.modificationDate(), modification == knownModification {
            now = .now
            return
        }
        let snapshot = persistence.load()
        knownModification = snapshot.modification
        apply(snapshot.data, userInitiated: false)
    }

    /// Merges copies of the data from other devices. Not undoable: it brings in what happened
    /// elsewhere rather than doing something here.
    func merge(_ remotes: [AppData]) {
        guard !remotes.isEmpty else { return }
        let result = persistence.update(stamping: false) { data in
            for remote in remotes { data = SyncMerge.merge(data, remote) }
        }
        knownModification = result.modification
        apply(result.after, userInitiated: false)
    }

    /// Replaces all data, e.g. from an import. The previous file is kept as a backup.
    func replaceAll(with newData: AppData) {
        let snapshot = persistence.replace(with: newData)
        knownModification = snapshot.modification
        apply(snapshot.data, userInitiated: false)
    }

    /// Daily backups, newest first.
    var dailyBackups: [URL] { persistence.dailyBackups() }

    /// The Focus filter in effect, unless the user chose to see past it.
    var activeFocusFilter: FocusFilter? {
        guard let focusFilter, focusFilter != ignoredFocusFilter else { return nil }
        return focusFilter
    }

    /// `goals` narrowed by the active Focus filter, keeping a running timer's goal.
    func filteredForFocus(_ goals: [Goal]) -> [Goal] {
        activeFocusFilter?.apply(to: goals, session: data.session) ?? goals
    }

    private func refreshFocusFilter() {
        guard persistence.watchedDirectory != nil else { return }
        let current = SharedStore.loadFocusFilter()
        if current != focusFilter {
            focusFilter = current
            if current == nil { ignoredFocusFilter = nil }
        }
    }

    private func apply(_ newData: AppData, userInitiated: Bool) {
        now = .now
        guard newData != data else { return }
        let previousData = data
        data = newData
        engine = ProgressEngine(data: newData)
        tipsCache = nil
        effects.dataDidChange(from: previousData, to: newData, engine: engine)
        if userInitiated { celebrateNewCompletions(from: previousData, to: newData) }
        if case .goal(let id) = route, newData.goal(id) == nil { route = .today }
        sync?.localDataDidChange()
        if previousData.session != newData.session || previousData.rest != newData.rest
            || previousData.preferences.pomodoro != newData.preferences.pomodoro {
            schedulePomodoro()
        }
        recordAchievements()
    }

    // MARK: - Pomodoro

    /// Wakes at the next Pomodoro boundary: the end of a block, or of a break.
    private func schedulePomodoro() {
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        guard data.preferences.pomodoro.isEnabled else { return }
        let next = data.session?.plannedEnd ?? data.rest.map(\.end)
        guard let next else { return }
        let timer = Timer(fire: max(next, .now.addingTimeInterval(0.2)), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.advancePomodoro() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pomodoroTimer = timer
    }

    /// Saves a finished block and starts its break, or starts the next block after a break.
    func advancePomodoro() {
        var event: PomodoroEvent?
        let settings = data.preferences.pomodoro
        let breakEnded = data.rest.map { settings.autoStartsNextBlock && $0.isOver(at: .now) } == true
        guard data.isBlockDue(at: .now) || breakEnded else { return }
        perform { event = $0.advancePomodoro() }
        guard let event else { return }
        switch event {
        case .blockCompleted: effects.play(.blockCompleted, preferences: data.preferences)
        case .blockStarted: effects.play(.blockStarted, preferences: data.preferences)
        }
    }

    func startNextBlock() { perform("Start Next Block") { $0.startNextBlock() } }

    func endRest() { perform("Skip Break") { $0.endRest() } }

    // MARK: - Achievements

    /// Records achievements the data has reached, announcing them.
    private func recordAchievements() {
        let earned = engine.newlyEarnedAchievements(now: .now)
        guard !earned.isEmpty else { return }
        perform { data in
            for achievement in earned where data.achievements[achievement.id] == nil {
                data.achievements[achievement.id] = .now
            }
        }
        if earned.count > 2 {
            show(Toast(kind: .achievements(earned.count)))
        } else {
            earned.forEach { show(Toast(kind: .achievement($0))) }
        }
        effects.play(.award, preferences: data.preferences)
    }

    // MARK: - Toasts

    func show(_ toast: Toast) {
        if self.toast == nil {
            self.toast = toast
        } else {
            toastQueue.append(toast)
        }
    }

    /// Hides the banner, then shows the next one waiting.
    func dismissToast() {
        toast = nil
        guard !toastQueue.isEmpty else { return }
        let next = toastQueue.removeFirst()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            self.toast = next
        }
    }

    // MARK: - Coach

    /// Today's tips, minus those dismissed. Cached per data version and minute.
    var coachTips: [CoachTip] {
        let minute = Int(Date().timeIntervalSince1970 / 60)
        let key = "\(minute)-\(dismissedTips.count)"
        if let tipsCache, tipsCache.key == key { return tipsCache.tips }
        let tips = engine.coachTips(now: .now, limit: 8).filter { !dismissedTips.contains($0.id) }.prefix(4)
        tipsCache = (key, Array(tips))
        return Array(tips)
    }

    func dismiss(_ tip: CoachTip) {
        dismissedTips.insert(tip.id)
        tipsCache = nil
        Self.saveDismissedTips(dismissedTips, on: .now)
    }

    func run(_ tip: CoachTip) {
        guard let action = tip.action else { return }
        switch action {
        case .startFocus(let id):
            if let goal = goal(id), !engine.isRunning(goal) { toggleFocus(goal) }
        case .log(let id):
            if let goal = goal(id) { quickAdd(goal) }
        case .open(let id):
            select(id)
        case .setTarget(let id, let target):
            perform("Change Target") { data in data.updateGoal(id) { $0.target = target } }
            dismiss(tip)
        case .planDay:
            sheet = .plan(DayID(.now))
        case .reflect:
            sheet = .reflect(DayID(.now))
        }
    }

    private static func dismissedTipsKey(on date: Date) -> String {
        "dismissedTips-\(DayID(date))"
    }

    private static func loadDismissedTips(on date: Date) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedTipsKey(on: date)) ?? [])
    }

    private static func saveDismissedTips(_ tips: Set<String>, on date: Date) {
        let defaults = UserDefaults.standard
        // Only today's list is kept.
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("dismissedTips-") && key != dismissedTipsKey(on: date) {
            defaults.removeObject(forKey: key)
        }
        defaults.set(Array(tips), forKey: dismissedTipsKey(on: date))
    }

    // MARK: - Journal

    func updateJournal(_ day: DayID, _ name: String = "Edit Journal", _ change: (inout JournalEntry) -> Void) {
        perform(name) { $0.updateJournal(for: day, change) }
    }

    func togglePriority(_ goal: Goal, on day: DayID = DayID(.now)) {
        perform("Change Priorities") { $0.togglePriority(goal.id, on: day) }
    }

    private func registerUndo(_ patch: DataPatch, name: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let result = store.persistence.update { patch.undo(on: &$0) }
                store.knownModification = result.modification
                store.apply(result.after, userInitiated: false)
                // Registering inside an undo makes it the redo.
                store.registerUndo(patch.reversed, name: name)
            }
        }
        undoManager.setActionName(name)
    }

    /// Celebrates goals this change completed. Both sides are judged on logged progress only: a
    /// running timer counts live, which would make a session's own goal look done already when it
    /// stops, and look newly done whenever anything else changes while it runs.
    private func celebrateNewCompletions(from previousData: AppData, to newData: AppData) {
        let moment = Date()
        var before = previousData
        before.session = nil
        var after = newData
        after.session = nil
        let previous = ProgressEngine(data: before)
        let current = ProgressEngine(data: after)
        for goal in current.activeGoals where current.isComplete(goal, now: moment) {
            guard let earlier = previous.goal(goal.id), !previous.isComplete(earlier, now: moment) else { continue }
            effects.play(.goalCompleted, preferences: data.preferences)
            if data.preferences.celebratesCompletion {
                let next = current.activeGoals.first { $0.stackAfter == goal.id && !current.isComplete($0, now: moment) && current.isScheduled($0, on: moment) }
                celebration = Celebration(goal: goal, next: next)
            }
            return
        }
    }

    // MARK: - Watching other processes

    private func watchForExternalChanges() {
        guard let directory = persistence.watchedDirectory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            logger.error("Could not watch \(directory.path, privacy: .public) for widget changes")
            return
        }
        // Saves are atomic renames, which register as writes to the folder rather than the file.
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func startDayTimer() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = Date()
                if !self.engine.calendar.isDate(current, inSameDayAs: self.now) {
                    self.now = current
                    self.dismissedTips = Self.loadDismissedTips(on: current)
                    self.tipsCache = nil
                    self.effects.dayDidChange(engine: self.engine)
                    self.persistence.backUpDaily()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dayTimer = timer
    }
}

// MARK: - Actions

extension GoalStore {
    func goal(_ id: UUID) -> Goal? { engine.goal(id) }

    func select(_ goalID: UUID) { route = .goal(goalID) }

    func toggleFocus(_ goal: Goal) {
        let running = engine.isRunning(goal)
        perform(running ? "Stop Focus" : "Start Focus") { $0.toggleFocus(on: goal.id) }
    }

    func startFocus(_ goal: Goal, minutes: Int?) {
        perform("Start Focus") { $0.startFocus(on: goal.id, planned: minutes.map { Double($0) * 60 }) }
    }

    func stopFocus() { perform("Stop Focus") { $0.stopFocus() } }

    func discardFocus() { perform("Discard Session") { $0.discardFocus() } }

    func togglePause() { perform { $0.togglePauseFocus() } }

    /// Adds five minutes to a planned session.
    func extendFocus(by minutes: Int = 5) {
        perform { data in
            guard let planned = data.session?.plannedDuration else { return }
            data.session?.plannedDuration = planned + Double(minutes * 60)
        }
    }

    func setSessionNote(_ note: String) { perform { $0.setSessionNote(note) } }

    func quickAdd(_ goal: Goal) { perform("Log Progress") { $0.quickAdd(to: goal.id) } }

    func log(_ amount: Double, for goal: Goal, at date: Date, note: String) {
        perform("Log Progress") { $0.log(amount, for: goal.id, at: date, note: note) }
    }

    func deleteEntry(_ entry: LogEntry) { perform("Delete Entry") { $0.deleteEntry(entry.id) } }

    func updateEntry(_ entry: LogEntry) { perform("Edit Entry") { $0.updateEntry(entry) } }

    func save(_ goal: Goal) { perform("Edit Goal") { $0.upsert(goal) } }

    func delete(_ goal: Goal) {
        perform("Delete Goal") { $0.deleteGoal(goal.id) }
    }

    func duplicate(_ goal: Goal) {
        var copyID: UUID?
        perform("Duplicate Goal") { copyID = $0.duplicateGoal(goal.id)?.id }
        if let copyID { route = .goal(copyID) }
    }

    func archive(_ goal: Goal) { perform("Archive Goal") { $0.archiveGoal(goal.id) } }

    func unarchive(_ goal: Goal) { perform("Restore Goal") { $0.unarchiveGoal(goal.id) } }

    func startBreak(_ goal: Goal, until: Date?) { perform("Take a Break") { $0.startBreak(for: goal.id, until: until) } }

    func endBreak(_ goal: Goal) { perform("End Break") { $0.endBreak(for: goal.id) } }

    func moveGoals(from source: IndexSet, to destination: Int) {
        perform("Reorder Goals") { $0.moveGoals(fromOffsets: source, toOffset: destination) }
    }

    func updatePreferences(_ change: (inout Preferences) -> Void) {
        perform { change(&$0.preferences) }
    }
}
