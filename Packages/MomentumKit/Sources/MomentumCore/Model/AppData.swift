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

    public init(id: UUID = UUID(), goalID: UUID, date: Date, amount: Double, source: Source = .manual, note: String = "", bookID: UUID? = nil) {
        self.id = id
        self.goalID = goalID
        self.date = date
        self.amount = amount
        self.source = source
        self.note = note
        self.bookID = bookID
    }

    private enum CodingKeys: String, CodingKey { case id, goalID, date, amount, source, note, bookID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(.id, default: UUID())
        goalID = try c.decode(UUID.self, forKey: .goalID)
        date = try c.decode(Date.self, forKey: .date)
        amount = try c.decode(.amount, default: 0)
        source = try c.decode(.source, default: .manual)
        note = try c.decode(.note, default: "")
        bookID = try c.decodeIfPresent(UUID.self, forKey: .bookID)
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

    public init(goalID: UUID, plannedDuration: TimeInterval? = nil, start: Date) {
        self.goalID = goalID
        self.plannedDuration = plannedDuration
        self.segments = []
        self.runningSince = start
        self.note = ""
    }

    public var isRunning: Bool { runningSince != nil }

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

    private enum CodingKeys: String, CodingKey { case goalID, plannedDuration, segments, runningSince, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goalID = try c.decode(UUID.self, forKey: .goalID)
        plannedDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .plannedDuration)
        segments = try c.decode(.segments, default: [])
        runningSince = try c.decodeIfPresent(Date.self, forKey: .runningSince)
        note = try c.decode(.note, default: "")
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

    public init(defaultFocusMinutes: Int = 25, celebratesCompletion: Bool = true, playsSounds: Bool = true, remindersEnabled: Bool = true,
                showsTimerInMenuBar: Bool = true, streakNudgesEnabled: Bool = true, streakNudgeMinute: Int = 20 * 60) {
        self.defaultFocusMinutes = defaultFocusMinutes
        self.celebratesCompletion = celebratesCompletion
        self.playsSounds = playsSounds
        self.remindersEnabled = remindersEnabled
        self.showsTimerInMenuBar = showsTimerInMenuBar
        self.streakNudgesEnabled = streakNudgesEnabled
        self.streakNudgeMinute = streakNudgeMinute
    }

    private enum CodingKeys: String, CodingKey {
        case defaultFocusMinutes, celebratesCompletion, playsSounds, remindersEnabled, showsTimerInMenuBar, streakNudgesEnabled, streakNudgeMinute
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
    }
}

/// Everything Momentum persists. The app and its widgets share one copy through the app group.
public struct AppData: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var goals: [Goal]
    public var entries: [LogEntry]
    public var session: FocusSession?
    public var preferences: Preferences

    public init(goals: [Goal] = [], entries: [LogEntry] = [], session: FocusSession? = nil, preferences: Preferences = Preferences()) {
        self.version = Self.currentVersion
        self.goals = goals
        self.entries = entries
        self.session = session
        self.preferences = preferences
    }

    private enum CodingKeys: String, CodingKey { case version, goals, entries, session, preferences }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(.version, default: Self.currentVersion)
        goals = try c.decode(.goals, default: [])
        entries = try c.decode(.entries, default: [])
        session = try c.decodeIfPresent(FocusSession.self, forKey: .session)
        preferences = try c.decode(.preferences, default: Preferences())
    }
}
