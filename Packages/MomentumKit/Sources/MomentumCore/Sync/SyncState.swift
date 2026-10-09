import Foundation

/// What syncing needs to know beyond the data itself: when each record last changed, and which
/// records were deleted. Every save records it (see `SyncStamper`), so any two copies of the
/// data can be merged later, whichever devices they came from.
///
/// Records are keyed "goal:<id>", "entry:<id>" and "journal:<day>", and the single values
/// "session", "rest", "preferences" and "order". An entry that was only ever added carries no
/// stamp: entries are almost never edited, and an unstamped record counts as old.
public struct SyncState: Codable, Equatable, Sendable {
    /// Record key -> when it last changed.
    public var stamps: [String: Date]
    /// Record key -> when it was deleted.
    public var tombstones: [String: Date]

    public init(stamps: [String: Date] = [:], tombstones: [String: Date] = [:]) {
        self.stamps = stamps
        self.tombstones = tombstones
    }

    /// Deletions are remembered this long, so a device that was away for months still learns of
    /// them; after that, a copy that never heard of one could bring the record back.
    public static let tombstoneLifetime: TimeInterval = 180 * 86_400

    public static func goal(_ id: UUID) -> String { "goal:\(id.uuidString)" }
    public static func entry(_ id: UUID) -> String { "entry:\(id.uuidString)" }
    public static func journal(_ day: DayID) -> String { "journal:\(day)" }
    public static let session = "session"
    public static let rest = "rest"
    public static let preferences = "preferences"
    public static let order = "order"

    public func stamp(_ key: String) -> Date { stamps[key] ?? .distantPast }

    /// Whether a record stamped `date` was deleted after that.
    public func isDeleted(_ key: String, stampedAt date: Date) -> Bool {
        guard let deleted = tombstones[key] else { return false }
        return deleted >= date
    }

    private enum CodingKeys: String, CodingKey { case stamps, tombstones }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stamps = try c.decode(.stamps, default: [:])
        tombstones = try c.decode(.tombstones, default: [:])
    }
}

/// Records what a save changed into the data's `SyncState`.
public enum SyncStamper {
    /// Stamps every record that differs between `before` and `after` at `now`, and leaves a
    /// tombstone for every record removed.
    public static func stamp(_ after: inout AppData, from before: AppData, at now: Date = .now) {
        var sync = after.sync
        func changed(_ key: String) {
            sync.stamps[key] = now
            sync.tombstones[key] = nil
        }
        func removed(_ key: String) {
            sync.stamps[key] = nil
            sync.tombstones[key] = now
        }

        if before.goals != after.goals {
            let old = Dictionary(before.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let new = Dictionary(after.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, goal) in new where old[id] != goal { changed(SyncState.goal(id)) }
            for id in old.keys where new[id] == nil { removed(SyncState.goal(id)) }
            if before.goals.map(\.id) != after.goals.map(\.id) { sync.stamps[SyncState.order] = now }
        }

        if before.entries != after.entries {
            let (oldStretch, newStretch) = changedStretch(before.entries, after.entries)
            let old = Dictionary(oldStretch.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let new = Dictionary(newStretch.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, entry) in new {
                let key = SyncState.entry(id)
                if let previous = old[id] {
                    if previous != entry { changed(key) }
                } else if sync.tombstones[key] != nil {
                    // Back after a delete (an undo): stamp it, so it outranks its own tombstone.
                    changed(key)
                }
            }
            for id in old.keys where new[id] == nil { removed(SyncState.entry(id)) }
        }

        if before.journal != after.journal {
            let old = Dictionary(before.journal.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
            let new = Dictionary(after.journal.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
            for (day, entry) in new where old[day] != entry { changed(SyncState.journal(day)) }
            for day in old.keys where new[day] == nil { removed(SyncState.journal(day)) }
        }

        if before.session != after.session { sync.stamps[SyncState.session] = now }
        if before.rest != after.rest { sync.stamps[SyncState.rest] = now }
        if before.preferences != after.preferences { sync.stamps[SyncState.preferences] = now }

        sync.tombstones = sync.tombstones.filter { now.timeIntervalSince($0.value) < SyncState.tombstoneLifetime }
        after.sync = sync
    }
}
