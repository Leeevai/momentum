import Foundation

/// One day at a glance, for the calendar.
public struct DaySummary: Hashable, Sendable {
    public var day: Date
    /// Daily goals that were due.
    public var due: [UUID]
    /// Due goals whose target was met.
    public var met: [UUID]
    /// Goals with any progress, due or not.
    public var active: [UUID]
    public var focusSeconds: Double
    public var journal: JournalEntry?

    /// The share of due goals met, or nil when nothing was due.
    public var completion: Double? {
        due.isEmpty ? nil : Double(met.count) / Double(due.count)
    }

    public var isPerfect: Bool { !due.isEmpty && met.count == due.count }
}

/// A stretch of focus on a day's timeline.
public struct TimelineBlock: Identifiable, Hashable, Sendable {
    public var goalID: UUID
    public var interval: DateInterval
    /// Part of the session running now.
    public var isLive: Bool

    public var id: String { "\(goalID)-\(interval.start.timeIntervalSince1970)-\(isLive)" }
}

extension ProgressEngine {
    public func daySummary(_ date: Date, now: Date) -> DaySummary {
        let day = startOfDay(date)
        var due: [UUID] = []
        var met: [UUID] = []
        var active: [UUID] = []
        var focus = 0.0
        for goal in data.goals {
            let existed = firstDay(of: goal) <= day && (goal.archivedAt.map { $0 > day } ?? true)
            if hasActivity(goal, on: day, now: now) {
                active.append(goal.id)
                if goal.kind == .time { focus += amount(for: goal, on: day, now: now) }
            }
            guard existed, day <= now, goal.effectivePeriod == .daily, goal.kind != .milestones, goal.kind != .books,
                  isRequired(goal, on: day) else { continue }
            due.append(goal.id)
            if isMet(goal, periodContaining: day, now: now) { met.append(goal.id) }
        }
        return DaySummary(day: day, due: due, met: met, active: active, focusSeconds: focus,
                          journal: data.journalEntry(for: DayID(day, calendar: calendar)))
    }

    /// The day's focus sessions in order, the running one included.
    public func timeline(on date: Date, now: Date) -> [TimelineBlock] {
        let interval = dayInterval(date)
        var blocks: [TimelineBlock] = data.entries.compactMap { entry in
            guard entry.source == .timer, entry.amount > 0, interval.holds(entry.date) else { return nil }
            let end = min(entry.date.addingTimeInterval(entry.amount), interval.end)
            return TimelineBlock(goalID: entry.goalID, interval: DateInterval(start: entry.date, end: end), isLive: false)
        }
        if let session = data.session {
            for segment in session.allSegments(at: now) {
                guard let clipped = segment.intersection(with: interval), clipped.duration > 0 else { continue }
                blocks.append(TimelineBlock(goalID: session.goalID, interval: clipped,
                                            isLive: session.isRunning && segment.end >= now.addingTimeInterval(-1)))
            }
        }
        return blocks.sorted { $0.interval.start < $1.interval.start }
    }

    /// `goals` with each stacked goal moved right after its anchor (and its own stack after it),
    /// keeping everything else in place. Cycles and missing anchors leave goals where they are.
    public func stackOrdered(_ goals: [Goal]) -> [Goal] {
        let ids = Set(goals.map(\.id))
        let followers = Dictionary(grouping: goals.filter { $0.stackAfter.map(ids.contains) ?? false && $0.stackAfter != $0.id },
                                   by: { $0.stackAfter! })
        var placed = Set<UUID>()
        var result: [Goal] = []
        func place(_ goal: Goal) {
            guard placed.insert(goal.id).inserted else { return }
            result.append(goal)
            for follower in followers[goal.id] ?? [] { place(follower) }
        }
        for goal in goals {
            // Stacked goals wait for their anchor, unless the stack loops back on itself.
            if let anchor = goal.stackAfter, ids.contains(anchor), anchor != goal.id, !stackLoops(from: goal, in: goals) { continue }
            place(goal)
        }
        for goal in goals where !placed.contains(goal.id) { place(goal) }
        return result
    }

    /// The anchors a goal is stacked after, nearest first.
    public func stackChain(of goal: Goal) -> [Goal] {
        var chain: [Goal] = []
        var seen: Set<UUID> = [goal.id]
        var current = goal
        while let anchorID = current.stackAfter, seen.insert(anchorID).inserted, let anchor = self.goal(anchorID) {
            chain.append(anchor)
            current = anchor
        }
        return chain
    }

    /// Goals that can be chosen as `goal`'s anchor: active, and not stacked after `goal` already.
    public func possibleAnchors(for goal: Goal) -> [Goal] {
        activeGoals.filter { candidate in
            candidate.id != goal.id && !stackChain(of: candidate).contains { $0.id == goal.id }
        }
    }

    private func stackLoops(from goal: Goal, in goals: [Goal]) -> Bool {
        let byID = Dictionary(goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<UUID> = [goal.id]
        var current = goal
        while let anchorID = current.stackAfter, let anchor = byID[anchorID] {
            if !seen.insert(anchorID).inserted { return true }
            current = anchor
        }
        return false
    }

    /// The weeks of a month, Monday or Sunday first per the calendar, padded with nil days.
    public func monthGrid(containing date: Date) -> [[Date?]] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leading)
        var day = month.start
        while day < month.end {
            days.append(day)
            day = self.day(1, from: day)
        }
        while days.count % 7 != 0 { days.append(nil) }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
    }
}

// MARK: - Mood

/// How mood and energy line up with progress.
public struct MoodReport: Hashable, Sendable {
    /// Average mood (1 to 5) on days most due goals were met, and on the others.
    public var moodOnGoodDays: Double?
    public var moodOnOtherDays: Double?
    /// Average focus per mood.
    public var focusByMood: [Mood: Double]
    public var averageMood: Double?
    public var averageEnergy: Double?
    /// Days with a mood recorded.
    public var days: Int
}

extension ProgressEngine {
    public func moodReport(in range: DateInterval, now: Date) -> MoodReport {
        var good: [Double] = []
        var other: [Double] = []
        var focus: [Mood: [Double]] = [:]
        var moods: [Double] = []
        var energies: [Double] = []
        for entry in data.journal {
            let day = entry.day.date(in: calendar)
            guard range.holds(day) else { continue }
            if let energy = entry.energy { energies.append(Double(energy.rawValue)) }
            guard let mood = entry.mood else { continue }
            moods.append(Double(mood.rawValue))
            let summary = daySummary(day, now: now)
            focus[mood, default: []].append(summary.focusSeconds)
            if let completion = summary.completion {
                if completion >= 0.75 { good.append(Double(mood.rawValue)) } else { other.append(Double(mood.rawValue)) }
            }
        }
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        return MoodReport(moodOnGoodDays: average(good), moodOnOtherDays: average(other),
                          focusByMood: focus.compactMapValues(average), averageMood: average(moods),
                          averageEnergy: average(energies), days: moods.count)
    }
}
