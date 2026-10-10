import Foundation

/// Answers every "how am I doing" question about the data, at a given moment.
///
/// Built once per data change: it indexes log entries by goal and day so the many per-render
/// queries (rings, streaks, heatmaps) are dictionary lookups rather than scans. A running focus
/// session is folded in live, so every query takes the current time.
public struct ProgressEngine: Sendable {
    public let data: AppData
    public let calendar: Calendar

    /// Goal id -> day key -> logged amount.
    let dailyTotals: [UUID: [Int: Double]]
    /// Goal id -> day keys with any activity (logs, finished milestones, finished books).
    let activityDays: [UUID: Set<Int>]
    /// Goal id -> the earliest day it has data for, so history from before creation still counts.
    private let firstDay: [UUID: Date]
    private let goalsByID: [UUID: Goal]
    private let streakCache = StreakCache()
    private let entryIndex = EntryIndex()

    public init(data: AppData, calendar: Calendar = .current) {
        // Entries for a goal that's gone (logged on another device after it was deleted here)
        // stay in the file for syncing, but count for nothing.
        let goalIDs = Set(data.goals.map(\.id))
        var data = data
        if data.entries.contains(where: { !goalIDs.contains($0.goalID) }) {
            data.entries.removeAll { !goalIDs.contains($0.goalID) }
        }
        self.data = data
        self.calendar = calendar
        var totals: [UUID: [Int: Double]] = [:]
        var activity: [UUID: Set<Int>] = [:]
        var first: [UUID: Date] = [:]
        for goal in data.goals {
            first[goal.id] = calendar.startOfDay(for: goal.createdAt)
        }
        // The earliest day key per goal, turned into a date once per goal: a calendar call per
        // entry is most of the cost of building an engine over years of history.
        var earliest: [UUID: Int] = [:]
        for entry in data.entries {
            let key = Self.dayKey(entry.date, calendar)
            totals[entry.goalID, default: [:]][key, default: 0] += entry.amount
            if entry.amount > 0 { activity[entry.goalID, default: []].insert(key) }
            if key < earliest[entry.goalID, default: .max] { earliest[entry.goalID] = key }
        }
        for (goalID, key) in earliest {
            let day = DayID(year: key / 10_000, month: key / 100 % 100, day: key % 100).date(in: calendar)
            if let known = first[goalID], day < known { first[goalID] = day }
        }
        for goal in data.goals {
            // Finishes count as history too: imported books carry past dates and no log entries.
            let finishes = goal.milestones.compactMap(\.completedAt) + goal.books.compactMap(\.finishedAt)
            for done in finishes {
                activity[goal.id, default: []].insert(Self.dayKey(done, calendar))
                let day = calendar.startOfDay(for: done)
                if let known = first[goal.id], day < known { first[goal.id] = day }
            }
        }
        dailyTotals = totals
        activityDays = activity
        firstDay = first
        goalsByID = Dictionary(data.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Lookup

    public func goal(_ id: UUID) -> Goal? { goalsByID[id] }

    public var activeGoals: [Goal] { data.goals.filter { !$0.isArchived } }

    public var archivedGoals: [Goal] { data.goals.filter(\.isArchived) }

    public func isRunning(_ goal: Goal) -> Bool { data.session?.goalID == goal.id }

    // MARK: - Calendar

    /// The local day `date` falls on, as yyyymmdd in the Gregorian calendar. Computed from the
    /// time zone's offset rather than through `Calendar`, which is far slower and is called for
    /// every log entry each time the engine is built.
    static func dayKey(_ date: Date, _ calendar: Calendar) -> Int {
        let (year, month, day) = DayMath.civil(DayMath.localDay(date, calendar.timeZone))
        return year * 10_000 + month * 100 + day
    }

    public func dayKey(_ date: Date) -> Int { Self.dayKey(date, calendar) }

    public func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// The start of the day `offset` days from `date`'s day.
    public func day(_ offset: Int, from date: Date) -> Date {
        let start = startOfDay(date)
        return calendar.date(byAdding: .day, value: offset, to: start) ?? start.addingTimeInterval(Double(offset) * 86_400)
    }

    public func dayInterval(_ date: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: startOfDay(date), duration: 86_400)
    }

    /// The period of `period` that contains `date`; an overall period spans all time.
    public func interval(of period: GoalPeriod, containing date: Date) -> DateInterval {
        guard let component = period.calendarComponent,
              let interval = calendar.dateInterval(of: component, for: date) else {
            return DateInterval(start: .distantPast, end: .distantFuture)
        }
        return interval
    }

    public func isScheduled(_ goal: Goal, on day: Date) -> Bool {
        goal.effectivePeriod != .daily || goal.weekdays.contains(calendar.component(.weekday, from: day))
    }

    /// Whether missing this day breaks a daily streak.
    public func isRequired(_ goal: Goal, on day: Date) -> Bool {
        isScheduled(goal, on: day) && !goal.isOnBreak(at: day)
    }

    /// The day `goal`'s history starts: its creation, or its earliest log if older.
    public func firstDay(of goal: Goal) -> Date {
        firstDay[goal.id] ?? startOfDay(goal.createdAt)
    }

    // MARK: - Amounts

    /// Seconds of the running session that fall inside `interval`.
    public func liveSeconds(for goal: Goal, in interval: DateInterval, now: Date) -> Double {
        guard let session = data.session, session.goalID == goal.id else { return 0 }
        return session.allSegments(at: now).reduce(0) { total, segment in
            total + (segment.intersection(with: interval)?.duration ?? 0)
        }
    }

    /// Logged amount on a day, plus the running session's share of it. Never negative.
    public func amount(for goal: Goal, on day: Date, now: Date) -> Double {
        let stored = dailyTotals[goal.id]?[dayKey(day)] ?? 0
        return max(0, stored + liveSeconds(for: goal, in: dayInterval(day), now: now))
    }

    /// Logged amount within `interval`, plus the running session's share of it.
    public func amount(for goal: Goal, in interval: DateInterval, now: Date) -> Double {
        guard interval.start > .distantPast else {
            let stored = dailyTotals[goal.id]?.values.reduce(0, +) ?? 0
            return max(0, stored + liveSeconds(for: goal, in: interval, now: now))
        }
        let live = liveSeconds(for: goal, in: interval, now: now)
        guard let days = dailyTotals[goal.id] else { return live }
        // A single day (the common case: streaks, rings) is one lookup.
        if interval.duration <= 25 * 3600 {
            return max(0, days[dayKey(interval.start)] ?? 0) + live
        }
        // Day keys sort chronologically (yyyymmdd), so a range is a filter over logged days.
        let first = dayKey(interval.start)
        let end = dayKey(interval.end)
        // A correction logged on another day (a page set back, a miscount) still applies to the
        // period, so days are summed as logged and only the total is floored at zero.
        var total = 0.0
        for (key, amount) in days where key >= first && key < end {
            total += amount
        }
        return max(0, total) + live
    }

    /// Every amount ever logged for the goal: time, count, amount, or pages read.
    public func lifetimeAmount(for goal: Goal, now: Date) -> Double {
        amount(for: goal, in: DateInterval(start: .distantPast, end: .distantFuture), now: now)
    }

    /// Books finished within `interval`.
    public func booksFinished(for goal: Goal, in interval: DateInterval) -> Int {
        goal.books.filter { book in
            guard book.status == .finished, let finished = book.finishedAt else { return false }
            return interval.holds(finished)
        }.count
    }

    // MARK: - Progress

    /// What counts toward the target in the period containing `date`:
    /// logged amount, books finished, or milestones completed.
    public func progressAmount(for goal: Goal, periodContaining date: Date, now: Date) -> Double {
        switch goal.kind {
        case .milestones:
            return Double(goal.milestones.filter(\.isDone).count)
        case .books:
            return Double(booksFinished(for: goal, in: interval(of: goal.effectivePeriod, containing: date)))
        case .time, .count, .amount:
            return amount(for: goal, in: interval(of: goal.effectivePeriod, containing: date), now: now)
        }
    }

    public func currentAmount(for goal: Goal, now: Date) -> Double {
        progressAmount(for: goal, periodContaining: now, now: now)
    }

    public func target(for goal: Goal) -> Double {
        goal.kind == .milestones ? Double(goal.milestones.count) : goal.target
    }

    /// Progress toward the current period's target, from 0 to 1.
    public func progress(for goal: Goal, now: Date) -> Double {
        let target = target(for: goal)
        guard target > 0 else { return 0 }
        return min(1, currentAmount(for: goal, now: now) / target)
    }

    /// Progress for a ring, which keeps going past the target: 1.5 is a lap and a half. Capped at
    /// two laps, where a ring has nothing left to show.
    public func ringProgress(for goal: Goal, now: Date) -> Double {
        let target = target(for: goal)
        guard target > 0 else { return 0 }
        return min(2, max(0, currentAmount(for: goal, now: now) / target))
    }

    public func isComplete(_ goal: Goal, now: Date) -> Bool {
        let target = target(for: goal)
        return target > 0 && currentAmount(for: goal, now: now) >= target
    }

    public func isMet(_ goal: Goal, periodContaining date: Date, now: Date) -> Bool {
        let target = target(for: goal)
        return target > 0 && progressAmount(for: goal, periodContaining: date, now: now) >= target
    }

    /// The amount that keeps a streak alive: the goal's minimum when it has one, else its target.
    public func streakThreshold(for goal: Goal) -> Double {
        let target = target(for: goal)
        guard goal.kind != .milestones, goal.kind != .books, let minimum = goal.streakMinimum, minimum > 0 else { return target }
        return min(minimum, target)
    }

    /// Whether the period did enough to keep the streak, which may be less than its target.
    public func keepsStreak(_ goal: Goal, periodContaining date: Date, now: Date) -> Bool {
        let threshold = streakThreshold(for: goal)
        return threshold > 0 && progressAmount(for: goal, periodContaining: date, now: now) >= threshold
    }

    /// Activity shade for a heatmap cell, from 0 to 1.
    public func intensity(for goal: Goal, on day: Date, now: Date) -> Double {
        let amount = amount(for: goal, on: day, now: now)
        let hasMarker = activityDays[goal.id]?.contains(dayKey(day)) ?? false
        let reference: Double
        switch goal.kind {
        case .milestones:
            return hasMarker ? 1 : 0
        case .books:
            // A day's reading compared with twice the quick-add step (20 pages by default).
            reference = max(1, goal.quickAddStep * 2)
        case .time, .count, .amount:
            switch goal.effectivePeriod {
            case .daily: reference = goal.target
            case .weekly: reference = goal.target / 7
            case .monthly: reference = goal.target / 30
            case .yearly: reference = goal.target / 365
            case .total:
                if let deadline = goal.deadline {
                    let days = max(1, calendar.dateComponents([.day], from: firstDay(of: goal), to: deadline).day ?? 1)
                    reference = goal.target / Double(days)
                } else {
                    reference = max(1, goal.quickAddStep)
                }
            }
        }
        guard reference > 0 else { return amount > 0 ? 1 : 0 }
        if amount <= 0 { return hasMarker ? 0.5 : 0 }
        return min(1, max(0.15, amount / reference))
    }

    public struct DailyAmount: Hashable, Sendable, Identifiable {
        public let day: Date
        public let amount: Double
        public var id: Date { day }
    }

    /// One value per day for the last `days` days, oldest first.
    public func dailyAmounts(for goal: Goal, days: Int, now: Date) -> [DailyAmount] {
        (0..<days).reversed().map { offset in
            let date = day(-offset, from: now)
            return DailyAmount(day: date, amount: amount(for: goal, on: date, now: now))
        }
    }

    // MARK: - Streaks

    public struct Streak: Equatable, Sendable {
        public var current: Int
        public var best: Int
        /// "day", "week", "month" or "year".
        public var unit: String
    }

    /// Consecutive periods with the target met, ending now.
    ///
    /// The current period adds to the streak once met but never breaks it while still open, and
    /// days that are unscheduled or on a break are skipped. Milestone and books goals count
    /// consecutive days with any activity instead, since their targets span months.
    public func streak(for goal: Goal, now: Date) -> Streak {
        if goal.kind == .milestones || goal.kind == .books || goal.effectivePeriod == .total {
            return activityStreak(for: goal, now: now)
        }
        if goal.effectivePeriod == .daily {
            return dailyStreak(for: goal, now: now)
        }
        return periodStreak(for: goal, now: now)
    }

    private static let maxStreakDays = 3_650
    /// How far back a weekly, monthly or yearly streak looks: over eleven years of weeks.
    private static let maxStreakPeriods = 600

    // Each streak is a pass over history (cached for the engine's lifetime: past periods can't
    // change while the data doesn't) plus the current period, checked live. The current period
    // adds to a streak once kept but never breaks it while still open.

    /// A key for a goal's streak history that changes whenever anything the history depends on
    /// does: its settings, its logged days and its finishes. Lets the history outlive the engine
    /// it was computed in, since most changes don't touch a goal's past.
    private func historyKey(_ kind: String, _ goal: Goal, _ anchor: Int) -> String {
        var hasher = Hasher()
        hasher.combine(goal.kind)
        hasher.combine(goal.period)
        hasher.combine(goal.target)
        hasher.combine(goal.streakMinimum)
        hasher.combine(goal.weekdays)
        hasher.combine(goal.breaks)
        hasher.combine(firstDay(of: goal))
        hasher.combine(goal.milestones.compactMap(\.completedAt))
        hasher.combine(goal.books.compactMap(\.finishedAt))
        // An order-independent sum of a full hash of each day's total: swapping amounts between
        // days, or moving entries forward and back, changes it.
        var totals = 0
        for (key, amount) in dailyTotals[goal.id] ?? [:] {
            var day = Hasher()
            day.combine(key)
            day.combine(amount)
            totals &+= day.finalize()
        }
        hasher.combine(totals)
        if let session = data.session, session.goalID == goal.id {
            hasher.combine(session.startedAt)
            hasher.combine(session.segments)
            hasher.combine(session.runningSince)
        }
        return "\(kind)|\(goal.id)|\(anchor)|\(hasher.finalize())"
    }

    private func dailyStreak(for goal: Goal, now: Date) -> Streak {
        let today = startOfDay(now)
        let history = streakCache.value(historyKey("d", goal, dayKey(today))) {
            var day = max(firstDay(of: goal), self.day(-Self.maxStreakDays, from: today))
            var run = 0
            var best = 0
            while day < today {
                if keepsStreak(goal, periodContaining: day, now: now) {
                    run += 1
                    best = max(best, run)
                } else if isRequired(goal, on: day) {
                    run = 0
                }
                day = self.day(1, from: day)
            }
            return StreakCache.Value(run: run, best: best)
        }
        return finish(history, currentKept: keepsStreak(goal, periodContaining: today, now: now), unit: "day")
    }

    private func periodStreak(for goal: Goal, now: Date) -> Streak {
        let period = goal.effectivePeriod
        guard let component = period.calendarComponent else { return Streak(current: 0, best: 0, unit: period.noun) }
        let current = interval(of: period, containing: now)
        let history = streakCache.value(historyKey("p", goal, dayKey(current.start))) {
            // The last `maxStreakPeriods` periods, counted back from now as the daily history is:
            // counted on from the first period, one entry from long ago stopped short of today.
            let earliest = calendar.date(byAdding: component, value: -Self.maxStreakPeriods, to: current.start) ?? current.start
            var start = interval(of: period, containing: max(firstDay(of: goal), earliest)).start
            var run = 0
            var best = 0
            var guardCount = 0
            while start < current.start && guardCount <= Self.maxStreakPeriods {
                guardCount += 1
                let periodInterval = interval(of: period, containing: start)
                if keepsStreak(goal, periodContaining: start, now: now) {
                    run += 1
                    best = max(best, run)
                } else if !goal.isOnBreak(at: periodInterval.start) {
                    run = 0
                }
                guard let next = calendar.date(byAdding: component, value: 1, to: periodInterval.start) else { break }
                start = next
            }
            return StreakCache.Value(run: run, best: best)
        }
        return finish(history, currentKept: keepsStreak(goal, periodContaining: now, now: now), unit: period.noun)
    }

    private func activityStreak(for goal: Goal, now: Date) -> Streak {
        let today = startOfDay(now)
        let days = activityDays[goal.id] ?? []
        let history = streakCache.value(historyKey("a", goal, dayKey(today))) {
            var day = max(firstDay(of: goal), self.day(-Self.maxStreakDays, from: today))
            var run = 0
            var best = 0
            while day < today {
                if days.contains(dayKey(day)) {
                    run += 1
                    best = max(best, run)
                } else if !goal.isOnBreak(at: day) {
                    run = 0
                }
                day = self.day(1, from: day)
            }
            return StreakCache.Value(run: run, best: best)
        }
        let activeToday = days.contains(dayKey(today)) || liveSeconds(for: goal, in: dayInterval(today), now: now) > 0
        return finish(history, currentKept: activeToday, unit: "day")
    }

    private func finish(_ history: StreakCache.Value, currentKept: Bool, unit: String) -> Streak {
        let current = history.run + (currentKept ? 1 : 0)
        return Streak(current: current, best: max(history.best, current), unit: unit)
    }

    /// Share of recent periods with the target met (30 days, 12 weeks, 12 months or 5 years).
    /// The current period counts only once met. Nil when nothing was due yet, or for goals
    /// without a repeating target.
    public func completionRate(for goal: Goal, now: Date) -> Double? {
        guard goal.kind != .milestones, goal.kind != .books else { return nil }
        let period = goal.effectivePeriod
        guard let component = period.calendarComponent else { return nil }
        let lookback: Int = switch period {
        case .daily: 30
        case .weekly, .monthly: 12
        default: 5
        }
        var due = 0
        var met = 0
        let first = firstDay(of: goal)
        for offset in 0..<lookback {
            guard let date = calendar.date(byAdding: component, value: -offset, to: now) else { continue }
            let periodInterval = interval(of: period, containing: date)
            guard periodInterval.end > first else { break }
            let isCurrent = offset == 0
            let wasMet = isMet(goal, periodContaining: date, now: now)
            if period == .daily && !isRequired(goal, on: date) && !wasMet { continue }
            if goal.isOnBreak(at: periodInterval.start) && !wasMet { continue }
            if isCurrent && !wasMet { continue }
            due += 1
            if wasMet { met += 1 }
        }
        return due == 0 ? nil : Double(met) / Double(due)
    }

    /// Whether a repeating goal is on target this week: a weekly goal that met its target, or a
    /// daily goal that met it on at least 70% of the week's due days so far. Nil for goals
    /// without a weekly rhythm (monthly, yearly, overall, books, milestones).
    public func isOnTargetThisWeek(_ goal: Goal, now: Date) -> Bool? {
        guard goal.kind != .milestones, goal.kind != .books else { return nil }
        switch goal.effectivePeriod {
        case .weekly:
            return isMet(goal, periodContaining: now, now: now)
        case .daily:
            let week = interval(of: .weekly, containing: now)
            var day = startOfDay(week.start)
            let today = startOfDay(now)
            var due = 0
            var met = 0
            while day <= today {
                if isRequired(goal, on: day) && day >= startOfDay(firstDay(of: goal)) {
                    due += 1
                    if isMet(goal, periodContaining: day, now: now) { met += 1 }
                }
                day = self.day(1, from: day)
            }
            return due == 0 ? nil : Double(met) / Double(due) >= 0.7
        default:
            return nil
        }
    }

    // MARK: - Today

    /// The goals that belong on today's list: active, not on a break, and either due today or
    /// already worked on today.
    public func todayGoals(now: Date) -> [Goal] {
        activeGoals.filter { goal in
            if isRunning(goal) { return true }
            if goal.isOnBreak(at: now) { return false }
            if goal.kind == .milestones { return !goal.milestones.isEmpty && !isComplete(goal, now: now) || hasActivity(goal, on: now, now: now) }
            if goal.effectivePeriod == .total && isComplete(goal, now: now) { return false }
            return isScheduled(goal, on: now) || hasActivity(goal, on: now, now: now)
        }
    }

    public func hasActivity(_ goal: Goal, on day: Date, now: Date) -> Bool {
        amount(for: goal, on: day, now: now) > 0 || (activityDays[goal.id]?.contains(dayKey(day)) ?? false)
    }

    public func todaySummary(now: Date) -> (done: Int, total: Int) {
        let goals = todayGoals(now: now)
        return (goals.filter { isComplete($0, now: now) }.count, goals.count)
    }

    public func longestCurrentStreak(now: Date) -> Int {
        activeGoals.map { streak(for: $0, now: now).current }.max() ?? 0
    }

    // MARK: - Pace

    public struct Pace: Equatable, Sendable {
        public enum Status: Equatable, Sendable { case done, onTrack, behind, noDeadline }

        public var status: Status
        public var remaining: Double
        public var deadline: Date?
        public var daysLeft: Int?
        /// What it takes per day from now to finish by the deadline.
        public var neededPerDay: Double?
        /// The average per day over the last 14 days.
        public var recentPerDay: Double
        /// When the goal finishes at the recent rate, if it is moving at all.
        public var projectedFinish: Date?
    }

    /// Progress against a deadline, for overall targets and for yearly, monthly and books goals.
    public func pace(for goal: Goal, now: Date) -> Pace? {
        let period = goal.effectivePeriod
        guard goal.kind != .milestones, period != .daily, period != .weekly else { return nil }
        let target = target(for: goal)
        guard target > 0 else { return nil }
        let done = currentAmount(for: goal, now: now)
        let remaining = max(0, target - done)
        let deadline: Date? = period == .total ? goal.deadline : interval(of: period, containing: now).end

        // The recent rate looks back 14 days (90 for books), or only as far as the goal goes.
        let age = (calendar.dateComponents([.day], from: firstDay(of: goal), to: startOfDay(now)).day ?? 0) + 1
        let lookback = max(1, min(goal.kind == .books ? 90 : 14, age))
        let window = DateInterval(start: day(-(lookback - 1), from: now), end: day(1, from: now))
        let recent: Double = goal.kind == .books
            ? Double(booksFinished(for: goal, in: window)) / Double(lookback)
            : amount(for: goal, in: window, now: now) / Double(lookback)

        let projected: Date? = recent > 0 ? now.addingTimeInterval(remaining / recent * 86_400) : nil
        guard remaining > 0 else {
            return Pace(status: .done, remaining: 0, deadline: deadline, daysLeft: nil, neededPerDay: nil, recentPerDay: recent, projectedFinish: nil)
        }
        guard let deadline else {
            return Pace(status: .noDeadline, remaining: remaining, deadline: nil, daysLeft: nil, neededPerDay: nil, recentPerDay: recent, projectedFinish: projected)
        }
        let daysLeft = max(0, calendar.dateComponents([.day], from: startOfDay(now), to: deadline).day ?? 0)
        let needed = remaining / Double(max(1, daysLeft))
        let onTrack = projected.map { $0 <= deadline } ?? false
        return Pace(status: onTrack ? .onTrack : .behind, remaining: remaining, deadline: deadline, daysLeft: daysLeft, neededPerDay: needed, recentPerDay: recent, projectedFinish: projected)
    }

    // MARK: - Sessions

    public struct SessionStats: Equatable, Sendable {
        public var count: Int
        public var average: TimeInterval
        public var longest: TimeInterval
    }

    /// Timer sessions logged for a goal. A session across midnight is logged per day, so it
    /// counts once per day it touched.
    public func sessionStats(for goal: Goal) -> SessionStats? {
        let sessions = entries(for: goal).filter { $0.source == .timer && $0.amount > 0 }
        guard !sessions.isEmpty else { return nil }
        let total = sessions.reduce(0) { $0 + $1.amount }
        return SessionStats(count: sessions.count, average: total / Double(sessions.count), longest: sessions.map(\.amount).max() ?? 0)
    }

    // MARK: - History

    /// A goal's log entries, newest first.
    public func entries(for goal: Goal) -> [LogEntry] {
        entryIndex.entries(for: goal.id, in: data.entries)
    }
}

/// Log entries grouped by goal, newest first, built on first use and kept for the engine's life.
final class EntryIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var byGoal: [UUID: [LogEntry]]?

    func entries(for goalID: UUID, in all: [LogEntry]) -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        if let byGoal { return byGoal[goalID] ?? [] }
        let grouped = Dictionary(grouping: all, by: \.goalID).mapValues { $0.sorted { $0.date > $1.date } }
        byGoal = grouped
        return grouped[goalID] ?? []
    }
}

/// Memoizes streak history. Keys fingerprint everything a history depends on, so a value never
/// goes stale; they are shared across engines (a new one is built on every change, and most
/// changes leave every goal's past alone), up to a bound.
final class StreakCache: @unchecked Sendable {
    struct Value: Sendable {
        var run: Int
        var best: Int
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var values: [String: Value] = [:]
    private static let limit = 2_000

    func value(_ key: String, compute: () -> Value) -> Value {
        Self.lock.lock()
        if let cached = Self.values[key] {
            Self.lock.unlock()
            return cached
        }
        Self.lock.unlock()
        let computed = compute()
        Self.lock.lock()
        if Self.values.count >= Self.limit { Self.values.removeAll(keepingCapacity: true) }
        Self.values[key] = computed
        Self.lock.unlock()
        return computed
    }
}
