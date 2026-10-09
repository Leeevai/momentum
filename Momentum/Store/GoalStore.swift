import AppKit
import MomentumCore
import Observation
import OSLog

enum Route: Hashable {
    case today
    case insights
    case goal(UUID)
}

enum SheetRoute: Identifiable {
    case quickActions
    case newGoal
    case editGoal(Goal)
    case log(goalID: UUID, entry: LogEntry? = nil)
    case link(goalID: UUID, link: GoalLink?)
    case book(goalID: UUID, book: Book?)
    case share(Goal)

    var id: String {
        switch self {
        case .quickActions: "quick-actions"
        case .newGoal: "new"
        case .editGoal(let goal): "edit-\(goal.id)"
        case .log(let id, let entry): "log-\(id)-\(entry?.id.uuidString ?? "new")"
        case .link(let goal, let link): "link-\(goal)-\(link?.id.uuidString ?? "new")"
        case .book(let goal, let book): "book-\(goal)-\(book?.id.uuidString ?? "new")"
        case .share(let goal): "share-\(goal.id)"
        }
    }
}

/// A goal that just reached its target, for the celebration overlay.
struct Celebration: Identifiable, Equatable {
    let id = UUID()
    let goal: Goal
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
    /// A goal awaiting delete confirmation.
    var confirmingDelete: Goal?
    /// Text typed in the sidebar search field.
    var searchText = ""

    /// The main window's undo manager, attached by the root view.
    @ObservationIgnored weak var undoManager: UndoManager?

    @ObservationIgnored let effects: SideEffects
    @ObservationIgnored private let persistence: DataPersistence
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var dayTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// The data file's modification date as of the last read or write by this app.
    @ObservationIgnored private var knownModification: Date?
    @ObservationIgnored private let logger = Logger(subsystem: "dev.momentum.app", category: "GoalStore")

    init(persistence: DataPersistence = SharedFilePersistence(), effects: SideEffects? = nil) {
        let initial = persistence.load()
        self.persistence = persistence
        self.knownModification = persistence.modificationDate()
        self.data = initial
        self.engine = ProgressEngine(data: initial)
        self.effects = effects ?? SideEffects()
        self.effects.attach(to: self)
        self.effects.start(with: initial, engine: engine)
        watchForExternalChanges()
        startDayTimer()
        persistence.backUpDaily()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })
    }

    /// An in-memory store with demo data, for previews and screenshots.
    static func preview(_ data: AppData = .demo()) -> GoalStore {
        GoalStore(persistence: InMemoryPersistence(data), effects: SideEffects(isEnabled: false))
    }

    // MARK: - Changing data

    /// Applies a change, saves it, and registers it for undo under `undoName`.
    func perform(_ undoName: String? = nil, _ change: (inout AppData) -> Void) {
        let previous = data
        let updated = persistence.update(change)
        knownModification = persistence.lastWriteModification()
        if let undoName { registerUndo(restoring: previous, name: undoName) }
        apply(updated, userInitiated: true)
    }

    /// Picks up changes made by the widgets or Shortcuts. The folder watcher also fires for the
    /// app's own saves; those leave the file as the app last saw it, so they are skipped.
    func reload() {
        let modification = persistence.modificationDate()
        if let modification, modification == knownModification {
            now = .now
            return
        }
        knownModification = modification
        apply(persistence.load(), userInitiated: false)
    }

    /// Replaces all data, e.g. from an import. The previous file is kept as a backup.
    func replaceAll(with newData: AppData) {
        persistence.replace(with: newData)
        knownModification = persistence.lastWriteModification()
        apply(persistence.load(), userInitiated: false)
    }

    /// Daily backups, newest first.
    var dailyBackups: [URL] { persistence.dailyBackups() }

    private func apply(_ newData: AppData, userInitiated: Bool) {
        now = .now
        guard newData != data else { return }
        let previousEngine = engine
        data = newData
        engine = ProgressEngine(data: newData)
        effects.dataDidChange(from: previousEngine.data, to: newData, engine: engine)
        if userInitiated { celebrateNewCompletions(since: previousEngine) }
        if case .goal(let id) = route, newData.goal(id) == nil { route = .today }
    }

    private func registerUndo(restoring snapshot: AppData, name: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let current = store.data
                store.apply(store.persistence.update { $0 = snapshot }, userInitiated: false)
                store.knownModification = store.persistence.lastWriteModification()
                store.registerUndo(restoring: current, name: name)
            }
        }
        undoManager.setActionName(name)
    }

    private func celebrateNewCompletions(since previous: ProgressEngine) {
        let moment = Date()
        for goal in engine.activeGoals where engine.isComplete(goal, now: moment) {
            guard let before = previous.goal(goal.id), !previous.isComplete(before, now: moment) else { continue }
            if data.preferences.playsSounds { NSSound(named: "Glass")?.play() }
            if data.preferences.celebratesCompletion { celebration = Celebration(goal: goal) }
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
