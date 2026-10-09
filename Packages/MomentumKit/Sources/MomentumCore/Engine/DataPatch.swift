import Foundation

/// The difference one action made, so it can be undone without disturbing anything that changed
/// afterwards (a widget starting a timer, a log from Shortcuts, another edit).
///
/// Undo works at the finest grain the data has: individual goal settings, milestones, books and
/// links by id, log entries by id, journal days, the session and break, preferences. Only what the
/// action itself changed is put back; everything else stays as it is now.
///
/// Achievements are left out on purpose: once earned, an achievement stays earned.
public struct DataPatch: Sendable {
    private var goals: [UUID: Change<Goal>] = [:]
    private var entries: [UUID: Change<LogEntry>] = [:]
    private var journal: [DayID: Change<JournalEntry>] = [:]
    private var session: Change<FocusSession>?
    private var rest: Change<RestPeriod>?
    private var preferences: Change<Preferences>?
    /// Goal order before and after, when the action reordered or added or removed goals.
    private var order: Change<[UUID]>?

    private struct Change<Value: Sendable>: Sendable {
        var before: Value?
        var after: Value?

        var reversed: Change { Change(before: after, after: before) }
    }

    public init(from before: AppData, to after: AppData) {
        let oldGoals = Self.byID(before.goals)
        let newGoals = Self.byID(after.goals)
        for id in Set(oldGoals.keys).union(newGoals.keys) where oldGoals[id] != newGoals[id] {
            goals[id] = Change(before: oldGoals[id], after: newGoals[id])
        }
        let oldOrder = before.goals.map(\.id)
        let newOrder = after.goals.map(\.id)
        if oldOrder != newOrder { order = Change(before: oldOrder, after: newOrder) }

        let (oldStretch, newStretch) = changedStretch(before.entries, after.entries)
        let oldEntries = Self.byID(Array(oldStretch))
        let newEntries = Self.byID(Array(newStretch))
        for id in Set(oldEntries.keys).union(newEntries.keys) where oldEntries[id] != newEntries[id] {
            entries[id] = Change(before: oldEntries[id], after: newEntries[id])
        }
        let oldJournal = Self.byID(before.journal)
        let newJournal = Self.byID(after.journal)
        for day in Set(oldJournal.keys).union(newJournal.keys) where oldJournal[day] != newJournal[day] {
            journal[day] = Change(before: oldJournal[day], after: newJournal[day])
        }
        if before.session != after.session { session = Change(before: before.session, after: after.session) }
        if before.rest != after.rest { rest = Change(before: before.rest, after: after.rest) }
        if before.preferences != after.preferences { preferences = Change(before: before.preferences, after: after.preferences) }
    }

    public var isEmpty: Bool {
        goals.isEmpty && entries.isEmpty && journal.isEmpty && session == nil && rest == nil && preferences == nil && order == nil
    }

    /// The patch that redoes what this one undoes.
    public var reversed: DataPatch {
        var patch = self
        patch.goals = goals.mapValues(\.reversed)
        patch.entries = entries.mapValues(\.reversed)
        patch.journal = journal.mapValues(\.reversed)
        patch.session = session?.reversed
        patch.rest = rest?.reversed
        patch.preferences = preferences?.reversed
        patch.order = order?.reversed
        return patch
    }

    /// Puts back what this action changed, leaving later changes alone.
    public func undo(on data: inout AppData) {
        // Goals first, so a goal this action deleted is back before its session and entries are.
        for (id, change) in goals {
            switch (change.before, change.after) {
            case (let previous?, nil):
                if data.goal(id) == nil { data.goals.append(previous) }
            case (let previous?, let changed?):
                data.updateGoal(id) { $0.revert(to: previous, from: changed) }
            case (nil, _):
                break
            }
        }
        let sessionRestored = undoSession(on: &data)
        // The action created these goals: remove them with anything logged to them since, so no
        // entry or running session is left pointing at nothing.
        for (id, change) in goals where change.before == nil {
            data.deleteGoal(id)
        }
        if let order, let previous = order.before {
            data.goals = Self.reordered(data.goals, like: previous)
        }

        for (id, change) in entries {
            // A stop's time stays logged when its session couldn't be put back, so focus time is
            // never lost to an undo.
            if !sessionRestored, change.before == nil, let entry = change.after, entry.source == .timer,
               entry.goalID == session?.before?.goalID {
                continue
            }
            if let previous = change.before {
                if data.goal(previous.goalID) == nil { continue }
                if let index = data.entries.firstIndex(where: { $0.id == id }) {
                    data.entries[index] = previous
                } else {
                    data.entries.append(previous)
                }
            } else {
                data.entries.removeAll { $0.id == id }
            }
        }
        for (day, change) in journal {
            // Field by field, so a mood synced in or written since survives undoing the plan.
            let empty = JournalEntry(day: day, modifiedAt: .distantPast)
            var entry = data.journalEntry(for: day) ?? empty
            entry.revert(to: change.before ?? empty, from: change.after ?? empty)
            data.journal.removeAll { $0.day == day }
            if !entry.isEmpty { data.journal.append(entry) }
        }
        data.journal.sort { $0.day < $1.day }
        // The break goes back only if it is still the one this action left, and never on top of
        // a session started since.
        if let rest, data.rest == rest.after, rest.before == nil || data.session == nil {
            data.rest = rest.before
        }
        if let previous = preferences?.before {
            data.preferences = previous
        }
        data.entries.sort { $0.date < $1.date }
    }

    /// Restores the session when the one there now is still the one this action left (pausing,
    /// resuming or noting it doesn't make it a different session). Returns whether it did.
    private func undoSession(on data: inout AppData) -> Bool {
        guard let session else { return true }
        guard Self.sameSession(data.session, session.after) else { return false }
        if let previous = session.before, data.goal(previous.goalID) == nil { return false }
        data.session = session.before
        return true
    }

    private static func sameSession(_ lhs: FocusSession?, _ rhs: FocusSession?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (let a?, let b?): a.goalID == b.goalID && a.startedAt == b.startedAt
        default: false
        }
    }

    private static func byID<T: Identifiable>(_ items: [T]) -> [T.ID: T] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// `goals` arranged in `order`; goals not mentioned keep their place at the end.
    private static func reordered(_ goals: [Goal], like order: [UUID]) -> [Goal] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return goals.enumerated()
            .sorted { (rank[$0.element.id] ?? order.count + $0.offset, $0.offset) < (rank[$1.element.id] ?? order.count + $1.offset, $1.offset) }
            .map(\.element)
    }
}

extension JournalEntry {
    /// Undoes the change from `previous` to `changed` field by field, keeping other edits.
    mutating func revert(to previous: JournalEntry, from changed: JournalEntry) {
        func field<T: Equatable>(_ keyPath: WritableKeyPath<JournalEntry, T>) {
            if previous[keyPath: keyPath] != changed[keyPath: keyPath] { self[keyPath: keyPath] = previous[keyPath: keyPath] }
        }
        field(\.intention)
        field(\.priorities)
        field(\.reflection)
        field(\.win)
        field(\.mood)
        field(\.energy)
    }
}

extension Goal {
    /// Undoes the change from `previous` to `changed`, field by field and item by item, keeping
    /// anything else that changed since.
    mutating func revert(to previous: Goal, from changed: Goal) {
        func field<T: Equatable>(_ keyPath: WritableKeyPath<Goal, T>) {
            if previous[keyPath: keyPath] != changed[keyPath: keyPath] { self[keyPath: keyPath] = previous[keyPath: keyPath] }
        }
        field(\.name)
        field(\.icon)
        field(\.symbol)
        field(\.color)
        field(\.category)
        field(\.details)
        field(\.kind)
        field(\.unit)
        field(\.period)
        field(\.target)
        field(\.streakMinimum)
        field(\.weekdays)
        field(\.deadline)
        field(\.quickAddStep)
        field(\.focusMinutes)
        field(\.reminder)
        field(\.stackAfter)
        field(\.breaks)
        field(\.createdAt)
        field(\.archivedAt)
        milestones = Self.revert(milestones, to: previous.milestones, from: changed.milestones)
        books = Self.revert(books, to: previous.books, from: changed.books)
        links = Self.revert(links, to: previous.links, from: changed.links)
    }

    /// Reverts the items that differ between `previous` and `changed` (by id), restoring their
    /// order if the change reordered them, and leaves every other item as it is in `current`.
    static func revert<T: Identifiable & Equatable>(_ current: [T], to previous: [T], from changed: [T]) -> [T] where T.ID: Hashable {
        let before = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(changed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result = current
        for id in Set(before.keys).union(after.keys) where before[id] != after[id] {
            if let item = before[id] {
                if let index = result.firstIndex(where: { $0.id == id }) {
                    result[index] = item
                } else {
                    let position = previous.firstIndex { $0.id == id } ?? result.count
                    result.insert(item, at: min(position, result.count))
                }
            } else {
                result.removeAll { $0.id == id }
            }
        }
        if previous.map(\.id) != changed.map(\.id) && Set(previous.map(\.id)) == Set(changed.map(\.id)) {
            let rank = Dictionary(previous.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            result = result.enumerated()
                .sorted { (rank[$0.element.id] ?? Int.max, $0.offset) < (rank[$1.element.id] ?? Int.max, $1.offset) }
                .map(\.element)
        }
        return result
    }
}
