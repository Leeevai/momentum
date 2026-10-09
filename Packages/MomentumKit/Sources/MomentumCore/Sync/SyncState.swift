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
    /// The goal order as last arranged (by a reorder, an add or a delete), stamped as "order".
    /// Nil until the first such change; the goals' own order stands in for it.
    public var order: [UUID]?
    /// Focus sessions that ended (stopped, discarded or replaced), by `sessionKey`, with when.
    /// It only grows, and merges by union, so a device can tell a session nobody ended (one the
    /// merge merely replaced with an older view of the timer) from one that ended elsewhere.
    public var endedSessions: [String: Date]
    /// Every focus session started, by `sessionKey`, with its start. Merged by union too, so a
    /// device settling a merge knows where a session it never saw began, and can end its own
    /// session there rather than count the same stretch twice.
    public var startedSessions: [String: Date]
    /// Sessions that ended and then came back (an undone stop), by `sessionKey`, with when. A
    /// session is ended while its end is later than its last return.
    public var resumedSessions: [String: Date]

    public init(stamps: [String: Date] = [:], tombstones: [String: Date] = [:], order: [UUID]? = nil,
                endedSessions: [String: Date] = [:], startedSessions: [String: Date] = [:], resumedSessions: [String: Date] = [:]) {
        self.stamps = stamps
        self.tombstones = tombstones
        self.order = order
        self.endedSessions = endedSessions
        self.startedSessions = startedSessions
        self.resumedSessions = resumedSessions
    }

    /// Whether a session has ended, on any device, since it last came back.
    public func hasEnded(_ session: FocusSession) -> Bool {
        let key = SyncState.sessionKey(session)
        guard let ended = endedSessions[key] else { return false }
        return resumedSessions[key].map { ended > $0 } ?? true
    }

    /// Names a session the same way on every device: its goal and the moment it started.
    public static func sessionKey(_ session: FocusSession) -> String {
        "\(session.goalID.uuidString)@\(session.startedAt.timeIntervalSinceReferenceDate)"
    }

    /// Deletions are remembered this long, so a device that was away for months still learns of
    /// them; after that, a copy that never heard of one could bring the record back.
    public static let tombstoneLifetime: TimeInterval = 180 * 86_400

    /// A device's file older than this is no longer merged. It's shorter than the life of a
    /// tombstone, so every file still merged has heard of every deletion it could undo: a device
    /// retired, or reinstalled under a new id, can't bring deleted records back. Only when no file
    /// in the folder is fresher, and this device has nothing yet, are stale files read: then there
    /// is no newer copy whose deletions they could undo.
    public static let peerLifetime: TimeInterval = 150 * 86_400

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

    private enum CodingKeys: String, CodingKey { case stamps, tombstones, order, endedSessions, startedSessions, resumedSessions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stamps = try c.decode(.stamps, default: [:])
        tombstones = try c.decode(.tombstones, default: [:])
        order = try c.decodeIfPresent([UUID].self, forKey: .order)
        endedSessions = try c.decode(.endedSessions, default: [:])
        startedSessions = try c.decode(.startedSessions, default: [:])
        resumedSessions = try c.decode(.resumedSessions, default: [:])
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
            if before.goals.map(\.id) != after.goals.map(\.id) {
                sync.stamps[SyncState.order] = now
                sync.order = after.goals.map(\.id)
            }
        }

        if before.entries != after.entries {
            let (oldStretch, newStretch) = changedStretch(before.entries, after.entries)
            let old = Dictionary(oldStretch.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let new = Dictionary(newStretch.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, entry) in new {
                let key = SyncState.entry(id)
                if let previous = old[id] {
                    if previous != entry { changed(key) }
                } else if sync.tombstones[key] != nil || entry.source == .timer {
                    // Back after a delete (an undo): stamp it, so it outranks its own tombstone.
                    // A timer entry's id is the same on every device that stops the session, so
                    // another device may hold a tombstone for it (stopped there, then undone):
                    // stamping it now keeps this later stop from losing to that older delete.
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

        if before.session != after.session {
            sync.stamps[SyncState.session] = now
            if let ended = before.session, after.session.map({ !$0.isSameSession(as: ended) }) ?? true {
                sync.endedSessions[SyncState.sessionKey(ended)] = now
            }
            if let started = after.session, before.session.map({ !$0.isSameSession(as: started) }) ?? true {
                let key = SyncState.sessionKey(started)
                sync.startedSessions[key] = started.startedAt
                // An ended session back again (an undone stop) is running once more.
                if sync.endedSessions[key] != nil { sync.resumedSessions[key] = now }
            }
        }
        if before.rest != after.rest { sync.stamps[SyncState.rest] = now }
        if before.preferences != after.preferences { sync.stamps[SyncState.preferences] = now }

        sync.tombstones = sync.tombstones.filter { now.timeIntervalSince($0.value) < SyncState.tombstoneLifetime }
        if sync.endedSessions.contains(where: { now.timeIntervalSince($0.value) >= SyncState.tombstoneLifetime }) {
            sync.endedSessions = sync.endedSessions.filter { now.timeIntervalSince($0.value) < SyncState.tombstoneLifetime }
        }
        if sync.startedSessions.contains(where: { now.timeIntervalSince($0.value) >= SyncState.tombstoneLifetime }) {
            sync.startedSessions = sync.startedSessions.filter { now.timeIntervalSince($0.value) < SyncState.tombstoneLifetime }
        }
        if sync.resumedSessions.contains(where: { now.timeIntervalSince($0.value) >= SyncState.tombstoneLifetime }) {
            sync.resumedSessions = sync.resumedSessions.filter { now.timeIntervalSince($0.value) < SyncState.tombstoneLifetime }
        }
        after.sync = sync
    }
}
