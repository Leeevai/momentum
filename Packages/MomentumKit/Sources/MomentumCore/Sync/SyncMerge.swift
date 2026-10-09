import Foundation

/// Merges two copies of the data, record by record: the most recent change to each record wins,
/// deletions stick unless the record changed again afterwards, and nothing logged on either side
/// is lost.
///
/// The merge is commutative and idempotent (merging A into B gives what merging B into A gives,
/// and merging again changes nothing), so devices that each merge whatever they find converge
/// on the same data, in any order and however often they sync.
public enum SyncMerge {
    public static func merge(_ local: AppData, _ remote: AppData) -> AppData {
        var sync = SyncState(stamps: local.sync.stamps.merging(remote.sync.stamps, uniquingKeysWith: max),
                             tombstones: local.sync.tombstones.merging(remote.sync.tombstones, uniquingKeysWith: max),
                             endedSessions: local.sync.endedSessions.merging(remote.sync.endedSessions, uniquingKeysWith: max))

        func pick<T: Codable & Equatable>(_ a: T?, _ b: T?, key: String, stampsA: SyncState, stampsB: SyncState) -> T? {
            switch (a, b) {
            case (nil, nil): return nil
            case (let only?, nil):
                return sync.isDeleted(key, stampedAt: stampsA.stamp(key)) ? nil : only
            case (nil, let only?):
                return sync.isDeleted(key, stampedAt: stampsB.stamp(key)) ? nil : only
            case (let first?, let second?):
                let firstStamp = stampsA.stamp(key)
                let secondStamp = stampsB.stamp(key)
                let winner: T
                if first == second || firstStamp > secondStamp {
                    winner = first
                } else if secondStamp > firstStamp {
                    winner = second
                } else {
                    winner = tieBreak(first, second)
                }
                return sync.isDeleted(key, stampedAt: max(firstStamp, secondStamp)) ? nil : winner
            }
        }

        // Goals, in the order of whichever side reordered last.
        let localGoals = Dictionary(local.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteGoals = Dictionary(remote.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var goals: [UUID: Goal] = [:]
        for id in Set(localGoals.keys).union(remoteGoals.keys) {
            goals[id] = pick(localGoals[id], remoteGoals[id], key: SyncState.goal(id), stampsA: local.sync, stampsB: remote.sync)
        }
        // The order is the list as last arranged on any device; goals it doesn't mention follow
        // in a fixed order, so the result is the same however merges are grouped.
        let order = single(local.sync.order ?? local.goals.map(\.id), remote.sync.order ?? remote.goals.map(\.id),
                           key: SyncState.order, local.sync, remote.sync) ?? []
        sync.order = order
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var merged = local
        merged.goals = goals.values.sorted { lhs, rhs in
            switch (rank[lhs.id], rank[rhs.id]) {
            case (let a?, let b?): a < b
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): (lhs.createdAt, lhs.id.uuidString) < (rhs.createdAt, rhs.id.uuidString)
            }
        }

        // Entries: the union, minus deletions. An entry whose goal is gone is kept, unseen (the
        // engine skips it): dropping it here would depend on the order copies are merged in.
        let localEntries = Dictionary(local.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteEntries = Dictionary(remote.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [LogEntry] = []
        entries.reserveCapacity(max(localEntries.count, remoteEntries.count))
        for id in Set(localEntries.keys).union(remoteEntries.keys) {
            if let entry = pick(localEntries[id], remoteEntries[id], key: SyncState.entry(id), stampsA: local.sync, stampsB: remote.sync) {
                entries.append(entry)
            }
        }
        merged.entries = entries.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id.uuidString < $1.id.uuidString }

        // Journal days.
        let localDays = Dictionary(local.journal.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteDays = Dictionary(remote.journal.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        merged.journal = Set(localDays.keys).union(remoteDays.keys).sorted().compactMap { day in
            pick(localDays[day], remoteDays[day], key: SyncState.journal(day), stampsA: local.sync, stampsB: remote.sync)
        }

        // Single values.
        // The session and the break each take their latest change. Plain last-writer-wins is what
        // keeps the merge associative: a copy merged in any grouping or order comes out the
        // same. Data that ends up with both a running session and a break, or a timer on a goal that
        // is gone, is settled by the app as a change of its own (`settleTimer`), which syncs.
        merged.session = single(local.session, remote.session, key: SyncState.session, local.sync, remote.sync)
        merged.rest = single(local.rest, remote.rest, key: SyncState.rest, local.sync, remote.sync)
        merged.preferences = single(local.preferences, remote.preferences, key: SyncState.preferences, local.sync, remote.sync) ?? local.preferences

        // Achievements stay earned, at the earliest date either side earned them.
        merged.achievements = local.achievements.merging(remote.achievements, uniquingKeysWith: min)
        merged.version = max(local.version, remote.version)

        // A tombstone outlived by a newer stamp has done its job; a stamp older than its
        // tombstone describes a record that no longer exists.
        let stamps = sync.stamps
        sync.tombstones = sync.tombstones.filter { key, deleted in (stamps[key] ?? .distantPast) <= deleted }
        sync.stamps = sync.stamps.filter { key, stamped in sync.tombstones[key].map { stamped > $0 } ?? true }
        merged.sync = sync
        return merged
    }

    /// The side whose single value changed last; nil values (no session) count as values.
    private static func single<T: Codable & Equatable>(_ a: T?, _ b: T?, key: String, _ stampsA: SyncState, _ stampsB: SyncState) -> T? {
        let first = stampsA.stamp(key)
        let second = stampsB.stamp(key)
        if a == b || first > second { return a }
        if second > first { return b }
        return tieBreak(a, b)
    }

    /// Picks the same one of two different values whichever side asks, by comparing their JSON:
    /// the longer one, then the greater. Longer first, because a version that doesn't know a
    /// field drops it when it reads a record and rewrites it unchanged otherwise; preferring the
    /// copy that still has the field keeps that version from erasing it everywhere.
    private static func tieBreak<T: Encodable>(_ a: T, _ b: T) -> T {
        // Full-precision dates: two values a fraction of a second apart must still differ here.
        let encoder = DateCoding.encoder()
        encoder.outputFormatting = .sortedKeys
        let first = (try? encoder.encode(a)) ?? Data()
        let second = (try? encoder.encode(b)) ?? Data()
        if first.count != second.count { return first.count > second.count ? a : b }
        return first.lexicographicallyPrecedes(second) ? b : a
    }
}
