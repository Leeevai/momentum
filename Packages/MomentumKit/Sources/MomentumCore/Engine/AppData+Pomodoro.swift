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

    /// Moves the Pomodoro rhythm along: saves a block that reached its length and starts its
    /// break, or starts the next block when a break ends and auto-start is on.
    @discardableResult
    public mutating func advancePomodoro(at now: Date = .now, calendar: Calendar = .current) -> PomodoroEvent? {
        if isBlockDue(at: now), let goalID = session?.goalID {
            completeFocusBlock(at: now, calendar: calendar)
            if let rest { return .blockCompleted(goalID: goalID, rest: rest) }
        }
        if let rest, preferences.pomodoro.isEnabled, preferences.pomodoro.autoStartsNextBlock, rest.isOver(at: now),
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
