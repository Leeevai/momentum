import Foundation

/// What `advancePomodoro` did, so the app can play a sound or post a notification.
public enum PomodoroEvent: Equatable, Sendable {
    /// A block reached its length and was saved; a break began.
    case blockCompleted(goalID: UUID, rest: RestPeriod)
    /// A break ended and the next block started by itself.
    case blockStarted(goalID: UUID, block: Int)
}

extension AppData {
    /// How late after a break ends the next block may still start by itself. Later than this
    /// (the Mac was asleep, say) it waits for the user rather than count time nobody focused.
    public static let autoStartGrace: TimeInterval = 90

    /// Whether the running session is a Pomodoro block that has reached its length.
    public func isBlockDue(at now: Date) -> Bool {
        guard preferences.pomodoro.isEnabled, let end = session?.plannedEnd else { return false }
        return end <= now
    }

    /// Settles what only merging two devices' copies can produce: a timer on a goal that's gone
    /// (it ends), and a running session alongside a break (the session wins, as starting one ends
    /// the break). Returns whether anything changed.
    @discardableResult
    public mutating func settleTimer() -> Bool {
        let before = (session, rest)
        if let session, goal(session.goalID) == nil { self.session = nil }
        if let rest, goal(rest.goalID) == nil { self.rest = nil }
        if session != nil { rest = nil }
        return before.0 != session || before.1 != rest
    }

    /// After merging other devices' copies in: a session that was running here before the merge,
    /// that no device has ended, and that the merge replaced (another device's older view of the
    /// timer won on time) is kept. If another session started meanwhile, this one stops where that
    /// one started, its time saved, as starting a session elsewhere would have done on one device.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func keepUnendedSession(_ local: FocusSession?, calendar: Calendar = .current) -> Bool {
        guard let local, session.map({ !$0.isSameSession(as: local) }) ?? true,
              sync.endedSessions[SyncState.sessionKey(local)] == nil, goal(local.goalID) != nil else { return false }
        if let other = session {
            session = local
            stopFocus(at: max(other.startedAt, local.startedAt), calendar: calendar)
            session = other
        } else {
            session = local
        }
        return true
    }

    /// Everything a device settles after merging others' copies in, as a change of its own.
    @discardableResult
    public mutating func settleAfterMerge(keeping local: FocusSession?, calendar: Calendar = .current) -> Bool {
        let kept = keepUnendedSession(local, calendar: calendar)
        let settled = settleTimer()
        return kept || settled
    }

    /// Moves the Pomodoro rhythm along: saves a block that reached its length and starts its
    /// break, or starts the next block when a break ends and auto-start is on. A break under a
    /// running session is left for `settleTimer`.
    @discardableResult
    public mutating func advancePomodoro(at now: Date = .now, calendar: Calendar = .current) -> PomodoroEvent? {
        if isBlockDue(at: now), let goalID = session?.goalID {
            completeFocusBlock(at: now, calendar: calendar)
            if let rest { return .blockCompleted(goalID: goalID, rest: rest) }
        }
        if session == nil, let rest, preferences.pomodoro.isEnabled, preferences.pomodoro.autoStartsNextBlock, rest.isOver(at: now),
           now.timeIntervalSince(rest.end) <= Self.autoStartGrace {
            startNextBlock(at: rest.end, calendar: calendar)
            if let session { return .blockStarted(goalID: session.goalID, block: session.block) }
        }
        return nil
    }

    /// Saves a block that reached its planned length, crediting exactly the planned time however
    /// late this runs, and starts a break from the moment the block ended.
    @discardableResult
    public mutating func completeFocusBlock(at now: Date = .now, calendar: Calendar = .current) -> [LogEntry] {
        guard isBlockDue(at: now), let finished = session, let plannedEnd = finished.plannedEnd,
              let planned = finished.plannedDuration else { return [] }
        let end = max(plannedEnd, finished.runningSince ?? plannedEnd)
        let logged = stopFocus(at: end, calendar: calendar)
        let settings = preferences.pomodoro
        let isLong = finished.block >= settings.blocksPerCycle
        let minutes = isLong ? settings.longBreakMinutes : settings.shortBreakMinutes
        rest = RestPeriod(goalID: finished.goalID, start: end, duration: Double(minutes) * 60, completedBlocks: finished.block,
                          blockDuration: planned, isLong: isLong)
        if isLong, achievements[Achievement.fullCycleID] == nil {
            achievements[Achievement.fullCycleID] = end
        }
        return logged
    }

    /// Ends the break and starts the next block on the same goal.
    public mutating func startNextBlock(at now: Date = .now, calendar: Calendar = .current) {
        guard let rest else { return }
        guard goal(rest.goalID)?.kind == .time, goal(rest.goalID)?.isArchived == false else {
            self.rest = nil
            return
        }
        startFocus(on: rest.goalID, planned: rest.blockDuration, at: now, calendar: calendar)
    }

    /// Ends the break without starting anything.
    public mutating func endRest() {
        rest = nil
    }
}
