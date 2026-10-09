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
                             tombstones: local.sync.tombstones.merging(remote.sync.tombstones, uniquingKeysWith: max))

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
        let localOrder = local.goals.map(\.id)
        let remoteOrder = remote.goals.map(\.id)
        let localFirst = local.sync.stamp(SyncState.order) > remote.sync.stamp(SyncState.order)
            || (local.sync.stamp(SyncState.order) == remote.sync.stamp(SyncState.order) && localOrder.map(\.uuidString).lexicographicallyPrecedes(remoteOrder.map(\.uuidString)))
        let order = (localFirst ? localOrder + remoteOrder : remoteOrder + localOrder).uniqued()

        var merged = local
        merged.goals = order.compactMap { goals[$0] }
        let goalIDs = Set(merged.goals.map(\.id))

        // Entries: the union, minus deletions; an entry whose goal is gone goes with it.
        let localEntries = Dictionary(local.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteEntries = Dictionary(remote.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [LogEntry] = []
        entries.reserveCapacity(max(localEntries.count, remoteEntries.count))
        for id in Set(localEntries.keys).union(remoteEntries.keys) {
            if let entry = pick(localEntries[id], remoteEntries[id], key: SyncState.entry(id), stampsA: local.sync, stampsB: remote.sync),
               goalIDs.contains(entry.goalID) {
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
        // The session: the same session on both sides takes its latest state; no session wins
        // over a session only where that session was seen to end; of two different sessions the
        // later one wins, since starting it ended the other there. A running session then
        // supersedes a break, as starting one always ends the break.
        merged.session = mergeSession(local, remote).flatMap { goalIDs.contains($0.goalID) ? $0 : nil }
        merged.rest = single(local.rest, remote.rest, key: SyncState.rest, local.sync, remote.sync)
            .flatMap { goalIDs.contains($0.goalID) ? $0 : nil }
        if merged.session != nil { merged.rest = nil }
        sync.endedSessions = Array(Set(local.sync.endedSessions + remote.sync.endedSessions).sorted().suffix(SyncState.endedSessionLimit))
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

    /// Whether `ender` saw `session` end, after the other side last changed it: a stop that
    /// happened before a resume (an undo, say) mustn't stop it again.
    private static func endedLater(_ session: FocusSession, by ender: AppData, than holder: AppData) -> Bool {
        ender.sync.endedSessions.contains(session.startedAt)
            && ender.sync.stamp(SyncState.session) >= holder.sync.stamp(SyncState.session)
    }

    private static func mergeSession(_ local: AppData, _ remote: AppData) -> FocusSession? {
        switch (local.session, remote.session) {
        case (nil, nil):
            return nil
        case (let only?, nil):
            return endedLater(only, by: remote, than: local) ? nil : only
        case (nil, let only?):
            return endedLater(only, by: local, than: remote) ? nil : only
        case (let a?, let b?):
            if a.isSameSession(as: b) {
                return single(a, b, key: SyncState.session, local.sync, remote.sync)
            }
            if a.startedAt != b.startedAt { return a.startedAt > b.startedAt ? a : b }
            return tieBreak(a, b)
        }
    }

    /// The side whose single value changed last; nil values (no session) count as values.
    private static func single<T: Codable & Equatable>(_ a: T?, _ b: T?, key: String, _ stampsA: SyncState, _ stampsB: SyncState) -> T? {
        let first = stampsA.stamp(key)
        let second = stampsB.stamp(key)
        if a == b || first > second { return a }
        if second > first { return b }
        return tieBreak(a, b)
    }

    /// Picks the same one of two different values whichever side asks, by comparing their JSON.
    private static func tieBreak<T: Encodable>(_ a: T, _ b: T) -> T {
        // Full-precision dates: two values a fraction of a second apart must still differ here.
        let encoder = DateCoding.encoder()
        encoder.outputFormatting = .sortedKeys
        let first = (try? encoder.encode(a)) ?? Data()
        let second = (try? encoder.encode(b)) ?? Data()
        return first.lexicographicallyPrecedes(second) ? b : a
    }
}
