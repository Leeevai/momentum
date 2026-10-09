import Foundation

/// The difference one action made, so it can be undone without disturbing anything that changed
/// afterwards (a widget starting a timer, a log from Shortcuts, another edit).
///
/// Undoing restores only the goals, entries, session and preferences this action touched, each
/// by id; everything else stays as it is now.
public struct DataPatch: Sendable {
    private var goals: [UUID: Change<Goal>] = [:]
    private var entries: [UUID: Change<LogEntry>] = [:]
    private var session: Change<FocusSession>?
    private var preferences: (before: Preferences, after: Preferences)?
    /// Goal order before and after, when the action reordered or added or removed goals.
    private var order: (before: [UUID], after: [UUID])?

    private struct Change<Value: Sendable>: Sendable {
        var before: Value?
        var after: Value?
    }

    public init(from before: AppData, to after: AppData) {
        let oldGoals = Dictionary(before.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newGoals = Dictionary(after.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in Set(oldGoals.keys).union(newGoals.keys) where oldGoals[id] != newGoals[id] {
            goals[id] = Change(before: oldGoals[id], after: newGoals[id])
        }
        let oldOrder = before.goals.map(\.id)
        let newOrder = after.goals.map(\.id)
        if oldOrder != newOrder { order = (oldOrder, newOrder) }

        let oldEntries = Dictionary(before.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newEntries = Dictionary(after.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in Set(oldEntries.keys).union(newEntries.keys) where oldEntries[id] != newEntries[id] {
            entries[id] = Change(before: oldEntries[id], after: newEntries[id])
        }
        if before.session != after.session { session = Change(before: before.session, after: after.session) }
        if before.preferences != after.preferences { preferences = (before.preferences, after.preferences) }
    }

    public var isEmpty: Bool {
        goals.isEmpty && entries.isEmpty && session == nil && preferences == nil && order == nil
    }

    /// The patch that redoes what this one undoes.
    public var reversed: DataPatch {
        var patch = self
        patch.goals = goals.mapValues { Change(before: $0.after, after: $0.before) }
        patch.entries = entries.mapValues { Change(before: $0.after, after: $0.before) }
        patch.session = session.map { Change(before: $0.after, after: $0.before) }
        patch.preferences = preferences.map { ($0.after, $0.before) }
        patch.order = order.map { ($0.after, $0.before) }
        return patch
    }

    /// Puts back what this action changed, leaving later changes to other things alone.
    public func undo(on data: inout AppData) {
        for (id, change) in goals {
            if let previous = change.before {
                data.upsert(previous)
            } else {
                data.goals.removeAll { $0.id == id }
            }
        }
        if let order {
            data.goals = Self.reordered(data.goals, like: order.before)
        }
        for (id, change) in entries {
            if let previous = change.before {
                if let index = data.entries.firstIndex(where: { $0.id == id }) {
                    data.entries[index] = previous
                } else {
                    data.entries.append(previous)
                }
            } else {
                data.entries.removeAll { $0.id == id }
            }
        }
        // A session started or stopped elsewhere since then wins over this action's.
        if let session, data.session == session.after {
            data.session = session.before
        }
        if let preferences {
            data.preferences = preferences.before
        }
        data.entries.sort { $0.date < $1.date }
    }

    /// `goals` arranged in `order`; goals not mentioned keep their place at the end.
    private static func reordered(_ goals: [Goal], like order: [UUID]) -> [Goal] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return goals.enumerated()
            .sorted { (rank[$0.element.id] ?? order.count + $0.offset, $0.offset) < (rank[$1.element.id] ?? order.count + $1.offset, $1.offset) }
            .map(\.element)
    }
}
