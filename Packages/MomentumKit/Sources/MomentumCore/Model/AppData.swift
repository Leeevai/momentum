import Foundation

/// One unit of logged progress.
public struct LogEntry: Codable, Identifiable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        case timer
        case manual
    }

    public var id: UUID
    public var goalID: UUID
    /// When the work happened (the start, for a timer session).
    public var date: Date
    /// Base units: seconds for time goals, pages for books, otherwise the goal's unit.
    /// Negative amounts are corrections.
    public var amount: Double
    public var source: Source
    public var note: String
    /// The book the pages were read in, for books goals.
    public var bookID: UUID?
    /// How the session went, if it was rated.
    public var quality: FocusQuality?

    public init(id: UUID = UUID(), goalID: UUID, date: Date, amount: Double, source: Source = .manual, note: String = "", bookID: UUID? = nil,
                quality: FocusQuality? = nil) {
        self.id = id
        self.goalID = goalID
        self.date = date
        self.amount = amount
        self.source = source
        self.note = note
        self.bookID = bookID
        self.quality = quality
    }

    private enum CodingKeys: String, CodingKey { case id, goalID, date, amount, source, note, bookID, quality }

    /// Leaves out values that are the decoding default (a manual entry, no note, no book): most
    /// entries are just an amount at a time, and the file is rewritten on every change.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(goalID, forKey: .goalID)
        try c.encode(date, forKey: .date)
        try c.encode(amount, forKey: .amount)
        if source != .manual { try c.encode(source, forKey: .source) }
        if !note.isEmpty { try c.encode(note, forKey: .note) }
        try c.encodeIfPresent(bookID, forKey: .bookID)
        try c.encodeIfPresent(quality, forKey: .quality)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(.id, default: UUID())
        goalID = try c.decode(UUID.self, forKey: .goalID)
        date = try c.decode(Date.self, forKey: .date)
        amount = try c.decode(.amount, default: 0)
        source = try c.decode(.source, default: .manual)
        note = try c.decode(.note, default: "")
        bookID = try c.decodeIfPresent(UUID.self, forKey: .bookID)
        // A rating this version doesn't know is dropped, not the entry.
        quality = (try? c.decodeIfPresent(FocusQuality.self, forKey: .quality)) ?? nil
    }
}

/// The focus timer. At most one runs at a time; pausing closes the current segment.
public struct FocusSession: Codable, Hashable, Sendable {
    public var goalID: UUID
    /// The planned length (a Pomodoro), or nil for an open-ended session.
    public var plannedDuration: TimeInterval?
    /// Finished stretches of focus, before the latest pause.
    public var segments: [DateInterval]
    /// Start of the stretch in progress; nil while paused.
    public var runningSince: Date?
    public var note: String
    /// Which block of a Pomodoro cycle this is, counting from 1.
    public var block: Int

    public init(goalID: UUID, plannedDuration: TimeInterval? = nil, start: Date, block: Int = 1) {
        self.goalID = goalID
        self.plannedDuration = plannedDuration
        self.segments = []
        self.runningSince = start
        self.note = ""
        self.block = block
    }

    public var isRunning: Bool { runningSince != nil }

    /// Whether `other` is this session, paused or resumed since: the same goal, started at the same moment.
    public func isSameSession(as other: FocusSession) -> Bool {
        goalID == other.goalID && startedAt == other.startedAt
    }

    public var startedAt: Date {
        segments.first?.start ?? runningSince ?? .distantPast
    }

    /// Focus time in finished segments.
    public var completedDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    /// Every segment, the one in progress closed at `now`.
    public func allSegments(at now: Date) -> [DateInterval] {
        guard let runningSince else { return segments }
        return segments + [DateInterval(start: runningSince, end: max(runningSince, now))]
    }

    public func elapsed(at now: Date) -> TimeInterval {
        allSegments(at: now).reduce(0) { $0 + $1.duration }
    }

    public func remaining(at now: Date) -> TimeInterval? {
        plannedDuration.map { $0 - elapsed(at: now) }
    }

    /// The date an elapsed-time counter would have started from, had it never paused.
    /// Lets widgets show a live counter with `Text(_:style: .timer)`.
    public var counterReferenceDate: Date? {
        runningSince.map { $0.addingTimeInterval(-completedDuration) }
    }

    /// When the planned length is reached, if the session is running and has one.
    public var plannedEnd: Date? {
        guard let reference = counterReferenceDate, let plannedDuration else { return nil }
        return reference.addingTimeInterval(plannedDuration)
    }

    private enum CodingKeys: String, CodingKey { case goalID, plannedDuration, segments, runningSince, note, block }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goalID = try c.decode(UUID.self, forKey: .goalID)
        plannedDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .plannedDuration)
        segments = try c.decode(.segments, default: [])
        runningSince = try c.decodeIfPresent(Date.self, forKey: .runningSince)
        note = try c.decode(.note, default: "")
        block = max(1, try c.decode(.block, default: 1))
    }
}

/// The Pomodoro rhythm: planned focus blocks chained with short breaks, and a long one after
/// every few blocks.
public struct PomodoroSettings: Codable, Hashable, Sendable {
    /// When on, a planned session that reaches its length is saved and a break begins.
    public var isEnabled: Bool
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int
    /// Blocks before a long break.
    public var blocksPerCycle: Int
    /// Starts the next block by itself when a break ends.
    public var autoStartsNextBlock: Bool

    public init(isEnabled: Bool = false, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 15, blocksPerCycle: Int = 4,
                autoStartsNextBlock: Bool = false) {
        self.isEnabled = isEnabled
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.blocksPerCycle = blocksPerCycle
        self.autoStartsNextBlock = autoStartsNextBlock
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, shortBreakMinutes, longBreakMinutes, blocksPerCycle, autoStartsNextBlock }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decode(.isEnabled, default: false)
        shortBreakMinutes = max(1, try c.decode(.shortBreakMinutes, default: 5))
        longBreakMinutes = max(1, try c.decode(.longBreakMinutes, default: 15))
        blocksPerCycle = max(1, try c.decode(.blocksPerCycle, default: 4))
        autoStartsNextBlock = try c.decode(.autoStartsNextBlock, default: false)
    }
}

/// A break between Pomodoro blocks.
public struct RestPeriod: Codable, Hashable, Sendable {
    /// The goal of the block just finished, which the next block continues.
    public var goalID: UUID
    public var start: Date
    public var duration: TimeInterval
    /// Blocks finished so far in this cycle, including the one before this break.
    public var completedBlocks: Int
    /// The length of the next block.
    public var blockDuration: TimeInterval
    public var isLong: Bool

    public init(goalID: UUID, start: Date, duration: TimeInterval, completedBlocks: Int, blockDuration: TimeInterval, isLong: Bool) {
        self.goalID = goalID
        self.start = start
        self.duration = duration
        self.completedBlocks = completedBlocks
        self.blockDuration = blockDuration
        self.isLong = isLong
    }

    public var end: Date { start.addingTimeInterval(duration) }

    public func remaining(at now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }

    public func isOver(at now: Date) -> Bool { now >= end }

    /// The block number the next session will be.
    public var nextBlock: Int { isLong ? 1 : completedBlocks + 1 }
}

/// Background noise played during a focus session.
public enum FocusSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case white
    case pink
    case brown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .off: "Off"
        case .white: "White noise"
        case .pink: "Pink noise"
        case .brown: "Brown noise (rain)"
        }
    }

    public var symbolName: String {
        switch self {
        case .off: "speaker.slash"
        case .white: "waveform"
        case .pink: "waveform.path"
        case .brown: "cloud.rain"
        }
    }
}

public struct Preferences: Codable, Hashable, Sendable {
    /// Offered first when starting a focus session on a goal with no default length.
    public var defaultFocusMinutes: Int
    public var celebratesCompletion: Bool
    public var playsSounds: Bool
    public var remindersEnabled: Bool
    public var showsTimerInMenuBar: Bool
    /// An evening nudge when a streak would break at midnight.
    public var streakNudgesEnabled: Bool
    /// Minutes after midnight for the streak nudge (20:00 by default).
    public var streakNudgeMinute: Int
    /// A summary notification on the last evening of each week.
    public var weeklyRecapEnabled: Bool
    public var focusSound: FocusSound
    /// From 0 to 1.
    public var focusSoundVolume: Double
    public var pomodoro: PomodoroSettings
    /// A morning prompt to plan the day, and an evening one to reflect on it.
    public var journalPromptsEnabled: Bool
    /// After a focus session, a one-tap question about how it went.
    public var asksSessionQuality: Bool
    /// The colors the app, its widgets and its watch app are drawn in.
    public var palette: ThemePalette

    public init(defaultFocusMinutes: Int = 25, celebratesCompletion: Bool = true, playsSounds: Bool = true, remindersEnabled: Bool = true,
                showsTimerInMenuBar: Bool = true, streakNudgesEnabled: Bool = true, streakNudgeMinute: Int = 20 * 60,
                weeklyRecapEnabled: Bool = true, focusSound: FocusSound = .off, focusSoundVolume: Double = 0.4,
                pomodoro: PomodoroSettings = PomodoroSettings(), journalPromptsEnabled: Bool = true, asksSessionQuality: Bool = true,
                palette: ThemePalette = .dusk) {
        self.defaultFocusMinutes = defaultFocusMinutes
        self.celebratesCompletion = celebratesCompletion
        self.playsSounds = playsSounds
        self.remindersEnabled = remindersEnabled
        self.showsTimerInMenuBar = showsTimerInMenuBar
        self.streakNudgesEnabled = streakNudgesEnabled
        self.streakNudgeMinute = streakNudgeMinute
        self.weeklyRecapEnabled = weeklyRecapEnabled
        self.focusSound = focusSound
        self.focusSoundVolume = focusSoundVolume
        self.pomodoro = pomodoro
        self.journalPromptsEnabled = journalPromptsEnabled
        self.asksSessionQuality = asksSessionQuality
        self.palette = palette
    }

    private enum CodingKeys: String, CodingKey {
        case defaultFocusMinutes, celebratesCompletion, playsSounds, remindersEnabled, showsTimerInMenuBar, streakNudgesEnabled, streakNudgeMinute
        case weeklyRecapEnabled, focusSound, focusSoundVolume, pomodoro, journalPromptsEnabled, asksSessionQuality, palette
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultFocusMinutes = try c.decode(.defaultFocusMinutes, default: 25)
        celebratesCompletion = try c.decode(.celebratesCompletion, default: true)
        playsSounds = try c.decode(.playsSounds, default: true)
        remindersEnabled = try c.decode(.remindersEnabled, default: true)
        showsTimerInMenuBar = try c.decode(.showsTimerInMenuBar, default: true)
        streakNudgesEnabled = try c.decode(.streakNudgesEnabled, default: true)
        streakNudgeMinute = try c.decode(.streakNudgeMinute, default: 20 * 60)
        weeklyRecapEnabled = try c.decode(.weeklyRecapEnabled, default: true)
        // An unknown sound from a newer version plays nothing rather than failing the file.
        focusSound = (try? c.decode(.focusSound, default: .off)) ?? .off
        focusSoundVolume = min(1, max(0, try c.decode(.focusSoundVolume, default: 0.4)))
        pomodoro = try c.decode(.pomodoro, default: PomodoroSettings())
        journalPromptsEnabled = try c.decode(.journalPromptsEnabled, default: true)
        asksSessionQuality = try c.decode(.asksSessionQuality, default: true)
        // A palette from a newer version draws in the default rather than failing the file.
        palette = (try? c.decode(.palette, default: .dusk)) ?? .dusk
    }
}

/// Everything Momentum persists. The app and its widgets share one copy through the app group.
public struct AppData: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var goals: [Goal]
    public var entries: [LogEntry]
    public var session: FocusSession?
    /// A break between Pomodoro blocks.
    public var rest: RestPeriod?
    public var preferences: Preferences
    /// Daily plans and reflections, oldest first.
    public var journal: [JournalEntry]
    /// Achievement id -> when it was earned.
    public var achievements: [String: Date]
    /// Change stamps and deletions, for merging copies from other devices.
    public var sync: SyncState

    public init(goals: [Goal] = [], entries: [LogEntry] = [], session: FocusSession? = nil, rest: RestPeriod? = nil,
                preferences: Preferences = Preferences(), journal: [JournalEntry] = [], achievements: [String: Date] = [:],
                sync: SyncState = SyncState()) {
        self.version = Self.currentVersion
        self.goals = goals
        self.entries = entries
        self.session = session
        self.rest = rest
        self.preferences = preferences
        self.journal = journal
        self.achievements = achievements
        self.sync = sync
    }

    private enum CodingKeys: String, CodingKey { case version, goals, entries, session, rest, preferences, journal, achievements, sync }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(.version, default: Self.currentVersion)
        goals = try c.decode(.goals, default: [])
        entries = try c.decode(.entries, default: [])
        session = try c.decodeIfPresent(FocusSession.self, forKey: .session)
        rest = try? c.decodeIfPresent(RestPeriod.self, forKey: .rest)
        preferences = try c.decode(.preferences, default: Preferences())
        journal = try c.decodeLossy(.journal)
        achievements = try c.decode(.achievements, default: [:])
        sync = (try? c.decode(.sync, default: SyncState())) ?? SyncState()
    }
}
