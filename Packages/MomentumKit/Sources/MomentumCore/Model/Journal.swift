import Foundation

/// A calendar day, independent of time zone: "2026-10-08". Journal entries are keyed by it so a
/// day written in one time zone is the same day read in another.
public struct DayID: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone, numbered in the Gregorian calendar
    /// whatever calendar the device uses, so every device names a day the same way.
    public init(_ date: Date, calendar: Calendar = .current) {
        let (year, month, day) = DayMath.civil(DayMath.localDay(date, calendar.timeZone))
        self.init(year: year, month: month, day: day)
    }

    /// Parses "yyyy-MM-dd".
    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// The start of this day in `calendar`'s time zone.
    public func date(in calendar: Calendar = .current) -> Date {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    public static func < (lhs: DayID, rhs: DayID) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = DayID(string: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a day: \(string)"))
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// How a day felt, from 1 (rough) to 5 (great). Drawn as weather rather than faces.
public enum Mood: Int, Codable, CaseIterable, Identifiable, Sendable {
    case rough = 1
    case low
    case okay
    case good
    case great

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .rough: "Rough"
        case .low: "Low"
        case .okay: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }

    public var symbolName: String {
        switch self {
        case .rough: "cloud.bolt.rain.fill"
        case .low: "cloud.drizzle.fill"
        case .okay: "cloud.fill"
        case .good: "cloud.sun.fill"
        case .great: "sun.max.fill"
        }
    }
}

/// Energy through the day, from 1 (drained) to 5 (charged).
public enum Energy: Int, Codable, CaseIterable, Identifiable, Sendable {
    case drained = 1
    case low
    case steady
    case high
    case charged

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .drained: "Drained"
        case .low: "Low"
        case .steady: "Steady"
        case .high: "High"
        case .charged: "Charged"
        }
    }

    public var symbolName: String {
        switch self {
        case .drained: "battery.0percent"
        case .low: "battery.25percent"
        case .steady: "battery.50percent"
        case .high: "battery.75percent"
        case .charged: "battery.100percent.bolt"
        }
    }
}

/// One day's plan and reflection: what you meant to do in the morning, how it went at night.
public struct JournalEntry: Codable, Identifiable, Hashable, Sendable {
    public var day: DayID
    /// The morning's intention, in a sentence.
    public var intention: String
    /// Up to three goals chosen as the day's priorities.
    public var priorities: [UUID]
    /// The evening's reflection.
    public var reflection: String
    /// Something that went well.
    public var win: String
    public var mood: Mood?
    public var energy: Energy?
    public var modifiedAt: Date

    public var id: DayID { day }

    public static let maxPriorities = 3

    public init(day: DayID, intention: String = "", priorities: [UUID] = [], reflection: String = "", win: String = "",
                mood: Mood? = nil, energy: Energy? = nil, modifiedAt: Date = .now) {
        self.day = day
        self.intention = intention
        self.priorities = priorities
        self.reflection = reflection
        self.win = win
        self.mood = mood
        self.energy = energy
        self.modifiedAt = modifiedAt
    }

    /// Whether anything was written or picked.
    public var isEmpty: Bool {
        intention.isEmpty && priorities.isEmpty && reflection.isEmpty && win.isEmpty && mood == nil && energy == nil
    }

    public var hasPlan: Bool { !intention.isEmpty || !priorities.isEmpty }

    public var hasReflection: Bool { !reflection.isEmpty || !win.isEmpty || mood != nil || energy != nil }

    private enum CodingKeys: String, CodingKey { case day, intention, priorities, reflection, win, mood, energy, modifiedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(DayID.self, forKey: .day)
        intention = try c.decode(.intention, default: "")
        priorities = try c.decode(.priorities, default: [])
        reflection = try c.decode(.reflection, default: "")
        win = try c.decode(.win, default: "")
        mood = try? c.decodeIfPresent(Mood.self, forKey: .mood)
        energy = try? c.decodeIfPresent(Energy.self, forKey: .energy)
        modifiedAt = try c.decode(.modifiedAt, default: .distantPast)
    }
}

extension AppData {
    public func journalEntry(for day: DayID) -> JournalEntry? {
        journal.first { $0.day == day }
    }

    /// Edits a day's entry, creating it if needed. An entry left empty is removed.
    public mutating func updateJournal(for day: DayID, at now: Date = .now, _ change: (inout JournalEntry) -> Void) {
        var entry = journalEntry(for: day) ?? JournalEntry(day: day, modifiedAt: now)
        let before = entry
        change(&entry)
        let existing = Set(goals.map(\.id))
        entry.priorities = Array(entry.priorities.uniqued().filter(existing.contains).prefix(JournalEntry.maxPriorities))
        guard entry != before else { return }
        entry.modifiedAt = now
        journal.removeAll { $0.day == day }
        if !entry.isEmpty {
            journal.append(entry)
            journal.sort { $0.day < $1.day }
        }
    }

    /// Adds `goalID` to the day's priorities, or removes it if it is there. Ignored once three
    /// are picked.
    public mutating func togglePriority(_ goalID: UUID, on day: DayID, at now: Date = .now) {
        // A deleted goal doesn't hold one of the three places.
        let existing = Set(goals.map(\.id))
        updateJournal(for: day, at: now) { entry in
            entry.priorities.removeAll { !existing.contains($0) }
            if let index = entry.priorities.firstIndex(of: goalID) {
                entry.priorities.remove(at: index)
            } else if entry.priorities.count < JournalEntry.maxPriorities {
                entry.priorities.append(goalID)
            }
        }
    }
}

extension Sequence where Element: Hashable {
    /// The elements in order, without repeats.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
