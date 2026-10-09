import Foundation

/// What a goal measures.
public enum GoalKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Focused time, tracked with a timer or logged by hand. Amounts are seconds.
    case time
    /// Discrete repetitions: workouts, check-ins, glasses of water.
    case count
    /// Any number with a unit: pages, kilometres, words, dollars.
    case amount
    /// A checklist of milestones; progress is the share completed.
    case milestones
    /// A reading list; progress is books finished, activity is pages read.
    case books

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .time: "Time"
        case .count: "Count"
        case .amount: "Amount"
        case .milestones: "Milestones"
        case .books: "Books"
        }
    }

    public var summary: String {
        switch self {
        case .time: "Focus sessions with a timer, e.g. 2 hours of deep work."
        case .count: "Things you do a number of times, e.g. 4 workouts a week."
        case .amount: "Any quantity with a unit, e.g. 20 pages or 5 km."
        case .milestones: "A project broken into steps you check off."
        case .books: "A reading list: log pages, finish books, hit a yearly target."
        }
    }

    public var symbolName: String {
        switch self {
        case .time: "timer"
        case .count: "checkmark.circle"
        case .amount: "number"
        case .milestones: "flag.checkered"
        case .books: "books.vertical"
        }
    }

    /// The default quick-add increment, in base units.
    public var defaultStep: Double {
        switch self {
        case .time: 15 * 60
        case .count, .milestones: 1
        case .amount: 1
        case .books: 10
        }
    }

    /// Milestone progress has no period: the checklist is the target.
    public var usesPeriod: Bool { self != .milestones }
}

/// How often a goal's target resets.
public enum GoalPeriod: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
    /// One cumulative target, optionally with a deadline.
    case total

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        case .total: "Overall"
        }
    }

    /// "day", "week", ...; empty for an overall target.
    public var noun: String {
        switch self {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        case .total: ""
        }
    }

    /// "Today", "This week", ...
    public var currentLabel: String {
        switch self {
        case .daily: "Today"
        case .weekly: "This week"
        case .monthly: "This month"
        case .yearly: "This year"
        case .total: "Overall"
        }
    }

    var calendarComponent: Calendar.Component? {
        switch self {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        case .total: nil
        }
    }
}

public enum GoalColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, brown, gray

    public var id: String { rawValue }
}

/// A web page, app deep link, or local file attached to a goal.
public struct GoalLink: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    /// A security-scoped bookmark for a local file or folder, so the sandboxed app can reopen it.
    public var bookmark: Data?
    /// Opened automatically when a focus session starts on the goal.
    public var opensWithFocus: Bool

    public init(id: UUID = UUID(), title: String, url: URL, bookmark: Data? = nil, opensWithFocus: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.bookmark = bookmark
        self.opensWithFocus = opensWithFocus
    }

    public var isFile: Bool { url.isFileURL }

    /// The title to show: the custom title, else the host or file name.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if url.isFileURL { return url.lastPathComponent }
        return url.host() ?? url.absoluteString
    }

    /// "github.com", "notion.so", or the parent folder of a file.
    public var subtitle: String {
        if url.isFileURL { return url.deletingLastPathComponent().path(percentEncoded: false) }
        if let host = url.host() { return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
        return url.scheme.map { "\($0)://" } ?? url.absoluteString
    }

    private enum CodingKeys: String, CodingKey { case id, title, url, bookmark, opensWithFocus }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(.id, default: UUID())
        title = try c.decode(.title, default: "")
        url = try c.decode(URL.self, forKey: .url)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        opensWithFocus = try c.decode(.opensWithFocus, default: false)
    }
}

public struct Milestone: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var dueDate: Date?
    public var completedAt: Date?

    public init(id: UUID = UUID(), title: String, dueDate: Date? = nil, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.completedAt = completedAt
    }

    public var isDone: Bool { completedAt != nil }

    private enum CodingKeys: String, CodingKey { case id, title, dueDate, completedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(.id, default: UUID())
        title = try c.decode(.title, default: "")
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

/// A notification at a fixed time, skipped on days the goal is already done. It can repeat
/// through the day ("drink water every two hours until 6 pm").
public struct ReminderSchedule: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var hour: Int
    public var minute: Int
    /// Repeat every this many minutes after the first reminder; nil for once a day.
    public var repeatMinutes: Int?
    /// The last time a repeating reminder may fire, in minutes after midnight.
    public var repeatUntilMinute: Int

    public init(isEnabled: Bool = true, hour: Int = 18, minute: Int = 0, repeatMinutes: Int? = nil, repeatUntilMinute: Int = 20 * 60) {
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.repeatMinutes = repeatMinutes
        self.repeatUntilMinute = repeatUntilMinute
    }

    /// Minutes after midnight of each reminder in a day.
    public var times: [Int] {
        let first = hour * 60 + minute
        guard let repeatMinutes, repeatMinutes > 0 else { return [first] }
        return Array(stride(from: first, through: max(first, min(repeatUntilMinute, 23 * 60 + 59)), by: repeatMinutes))
    }

    private enum CodingKeys: String, CodingKey { case isEnabled, hour, minute, repeatMinutes, repeatUntilMinute }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decode(.isEnabled, default: true)
        hour = try c.decode(.hour, default: 18)
        minute = try c.decode(.minute, default: 0)
        repeatMinutes = try c.decodeIfPresent(Int.self, forKey: .repeatMinutes)
        repeatUntilMinute = try c.decode(.repeatUntilMinute, default: 20 * 60)
    }
}

/// Preset categories offered in the editor. Any other text is allowed too.
public enum GoalCategory {
    public static let presets = ["Work", "Learning", "Reading", "Health", "Fitness", "Mindfulness", "Creative", "Finance", "Personal"]
}

public struct Goal: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// The emoji icon of versions before 2.0, kept so older files and apps still read it.
    public var icon: String
    /// The goal's icon: an SF Symbol name from `SymbolCatalog`.
    public var symbol: String
    public var color: GoalColor
    /// Free-form grouping shown in the sidebar; empty means uncategorized.
    public var category: String
    /// Why this goal matters, or any notes.
    public var details: String
    public var kind: GoalKind
    /// Unit for count and amount goals ("workouts", "pages"). Books always count books.
    public var unit: String
    public var period: GoalPeriod
    /// Target per period in base units (seconds for time goals). Milestone goals use their checklist.
    public var target: Double
    /// A smaller amount that still keeps the streak alive on a hard day (the "two-minute rule").
    /// The ring and "done" still use the full target. Nil means only the full target counts.
    public var streakMinimum: Double?
    /// Weekdays a daily goal is scheduled on (1 = Sunday ... 7 = Saturday).
    public var weekdays: Set<Int>
    /// Optional deadline for an overall target.
    public var deadline: Date?
    /// The increment of the quick-add button, in base units (pages for books).
    public var quickAddStep: Double
    /// Default focus-session length; nil runs an open-ended timer.
    public var focusMinutes: Int?
    public var links: [GoalLink]
    public var milestones: [Milestone]
    public var books: [Book]
    public var reminder: ReminderSchedule?
    /// Habit stacking: this goal comes right after another one ("after coffee, read"). Today lists
    /// it after its anchor, and finishing the anchor suggests it.
    public var stackAfter: UUID?
    /// Breaks protect the streak: days inside one are never required.
    public var breaks: [DateInterval]
    /// A run of days to keep the goal going, if one was started.
    public var challenge: Challenge?
    public var createdAt: Date
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String = "🎯",
        symbol: String? = nil,
        color: GoalColor = .blue,
        category: String = "",
        details: String = "",
        kind: GoalKind = .time,
        unit: String = "",
        period: GoalPeriod = .daily,
        target: Double,
        streakMinimum: Double? = nil,
        weekdays: Set<Int> = Set(1...7),
        deadline: Date? = nil,
        quickAddStep: Double? = nil,
        focusMinutes: Int? = nil,
        links: [GoalLink] = [],
        milestones: [Milestone] = [],
        books: [Book] = [],
        reminder: ReminderSchedule? = nil,
        stackAfter: UUID? = nil,
        breaks: [DateInterval] = [],
        challenge: Challenge? = nil,
        createdAt: Date = .now,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.symbol = symbol ?? SymbolCatalog.symbol(forEmoji: icon) ?? SymbolCatalog.defaultSymbol(for: kind)
        self.color = color
        self.category = category
        self.details = details
        self.kind = kind
        self.unit = unit
        self.period = period
        self.target = target
        self.streakMinimum = streakMinimum
        self.weekdays = weekdays
        self.deadline = deadline
        self.quickAddStep = quickAddStep ?? kind.defaultStep
        self.focusMinutes = focusMinutes
        self.links = links
        self.milestones = milestones
        self.books = books
        self.reminder = reminder
        self.stackAfter = stackAfter
        self.breaks = breaks
        self.challenge = challenge
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }

    /// Copies what the goal editor edits, leaving links, milestones, books, breaks, archive state
    /// and creation date alone.
    public mutating func applySettings(from other: Goal) {
        name = other.name
        icon = other.icon
        symbol = other.symbol
        color = other.color
        category = other.category
        details = other.details
        kind = other.kind
        unit = other.unit
        period = other.period
        target = other.target
        streakMinimum = other.streakMinimum
        weekdays = other.weekdays
        deadline = other.deadline
        quickAddStep = other.quickAddStep
        focusMinutes = other.focusMinutes
        reminder = other.reminder
        stackAfter = other.stackAfter == id ? nil : other.stackAfter
        challenge = other.challenge
    }

    /// The period progress is measured over; milestone goals are always overall.
    public var effectivePeriod: GoalPeriod { kind.usesPeriod ? period : .total }

    public func isOnBreak(at date: Date) -> Bool {
        breaks.contains { $0.start <= date && date < $0.end }
    }

    /// The break in effect now, if any.
    public func activeBreak(at date: Date) -> DateInterval? {
        breaks.first { $0.start <= date && date < $0.end }
    }

    /// The book currently being read: the one most recently started among those in progress.
    public var currentBook: Book? {
        books.filter { $0.status == .reading }.max { ($0.startedAt ?? $0.addedAt) < ($1.startedAt ?? $1.addedAt) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, symbol, color, category, details, kind, unit, period, target, streakMinimum, weekdays, deadline
        case quickAddStep, focusMinutes, links, milestones, books, reminder, stackAfter, breaks, challenge, createdAt, archivedAt
    }

    /// Written out by hand only so the weekdays come out sorted: a set's order differs from one
    /// run of the app to the next, and sync compares records by their encoding.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(color, forKey: .color)
        try c.encode(category, forKey: .category)
        try c.encode(details, forKey: .details)
        try c.encode(kind, forKey: .kind)
        try c.encode(unit, forKey: .unit)
        try c.encode(period, forKey: .period)
        try c.encode(target, forKey: .target)
        try c.encodeIfPresent(streakMinimum, forKey: .streakMinimum)
        try c.encode(weekdays.sorted(), forKey: .weekdays)
        try c.encodeIfPresent(deadline, forKey: .deadline)
        try c.encode(quickAddStep, forKey: .quickAddStep)
        try c.encodeIfPresent(focusMinutes, forKey: .focusMinutes)
        try c.encode(links, forKey: .links)
        try c.encode(milestones, forKey: .milestones)
        try c.encode(books, forKey: .books)
        try c.encodeIfPresent(reminder, forKey: .reminder)
        try c.encodeIfPresent(stackAfter, forKey: .stackAfter)
        try c.encode(breaks, forKey: .breaks)
        try c.encodeIfPresent(challenge, forKey: .challenge)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(archivedAt, forKey: .archivedAt)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(.id, default: UUID())
        name = try c.decode(.name, default: "Untitled")
        icon = try c.decode(.icon, default: "🎯")
        let decodedKind = try c.decode(.kind, default: GoalKind.time)
        // Goals from before symbols get the closest match to their emoji.
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
            ?? SymbolCatalog.symbol(forEmoji: icon) ?? SymbolCatalog.defaultSymbol(for: decodedKind)
        // Cosmetic values from a newer version fall back rather than make the whole file unreadable.
        color = (try? c.decode(.color, default: .blue)) ?? .blue
        category = try c.decode(.category, default: "")
        details = try c.decode(.details, default: "")
        kind = try c.decode(.kind, default: .time)
        unit = try c.decode(.unit, default: "")
        period = try c.decode(.period, default: .daily)
        target = try c.decode(.target, default: 0)
        streakMinimum = try c.decodeIfPresent(Double.self, forKey: .streakMinimum)
        weekdays = try c.decode(.weekdays, default: Set(1...7))
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        quickAddStep = try c.decode(.quickAddStep, default: kind.defaultStep)
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes)
        links = try c.decode(.links, default: [])
        milestones = try c.decode(.milestones, default: [])
        books = try c.decode(.books, default: [])
        reminder = try c.decodeIfPresent(ReminderSchedule.self, forKey: .reminder)
        stackAfter = try c.decodeIfPresent(UUID.self, forKey: .stackAfter)
        breaks = try c.decode(.breaks, default: [])
        // A challenge from a newer version that this one can't read is dropped, not the goal.
        challenge = (try? c.decodeIfPresent(Challenge.self, forKey: .challenge)) ?? nil
        createdAt = try c.decode(.createdAt, default: .now)
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}
