import Foundation

/// What the Apple Watch shows, worked out on the iPhone: today's goals with their progress, the
/// timer, and each goal's one-tap action. A few kilobytes, so it can go out on every change.
public struct WatchSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var name: String
        public var symbol: String
        public var color: GoalColor
        public var kind: GoalKind
        /// From 0 to 1 (and past 1 when beaten).
        public var progress: Double
        /// "45m / 2h", "2 / 4 workouts".
        public var progressText: String
        public var streak: Int
        public var streakUnit: String
        public var isComplete: Bool
        /// The one-tap action for goals without a timer: "+1", "+10 pages", "Done"; nil if none.
        public var actionTitle: String?
        /// The target alone ("2h", "4 workouts"), to show a fresh period's progress before the
        /// iPhone has sent one.
        public var targetText: String
        /// When the period this progress counts toward ends (nil for an overall target).
        public var periodEnd: Date?
        /// What reaching the target is called for this goal: "Done for today", "Done this week".
        public var doneText: String
        /// The day of a running challenge, and its length.
        public var challengeDay: Int?
        public var challengeLength: Int?

        private enum CodingKeys: String, CodingKey {
            case id, name, symbol, color, kind, progress, progressText, streak, streakUnit, isComplete, actionTitle, targetText
            case periodEnd, doneText, challengeDay, challengeLength
        }
    }

    public var items: [Item]
    public var session: FocusSession?
    public var rest: RestPeriod?
    /// Today's goals done, of all of them.
    public var done: Int
    public var total: Int
    public var generatedAt: Date
    /// The day the snapshot describes.
    public var day: DayID
    /// The iPhone's palette; nil from an iPhone that doesn't send one, and the watch draws in the
    /// default palette.
    public var palette: WatchPalette?

    public init(items: [Item] = [], session: FocusSession? = nil, rest: RestPeriod? = nil, done: Int = 0, total: Int = 0,
                generatedAt: Date = .distantPast, day: DayID = DayID(year: 2001, month: 1, day: 1), palette: WatchPalette? = nil) {
        self.items = items
        self.session = session
        self.rest = rest
        self.done = done
        self.total = total
        self.generatedAt = generatedAt
        self.day = day
        self.palette = palette
    }

    /// The snapshot as it stands at `date`: goals whose period has ended since (each day for a
    /// daily goal, at the week's end for a weekly one) start over with nothing done, so the
    /// watch never shows a finished period's progress as the current one's. The rest (streaks,
    /// the timer) carries over until the iPhone sends a new snapshot.
    public func current(at date: Date, calendar: Calendar = .current) -> WatchSnapshot {
        guard items.contains(where: { ($0.periodEnd ?? .distantFuture) <= date }) || DayID(date, calendar: calendar) > day else { return self }
        var fresh = self
        var reopened = 0
        fresh.items = items.map { item in
            guard let end = item.periodEnd, end <= date else { return item }
            var item = item
            if item.isComplete { reopened += 1 }
            item.progress = 0
            item.isComplete = false
            item.progressText = item.kind == .time ? "0m / \(item.targetText)" : "0 / \(item.targetText)"
            return item
        }
        fresh.done = max(0, done - reopened)
        fresh.day = max(day, DayID(date, calendar: calendar))
        return fresh
    }

    /// The most goals sent: a watch screen's worth, and then some.
    public static let itemLimit = 12

    public func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    /// The snapshot as sent: dates exact, like the data file.
    public func encoded() throws -> Data { try DateCoding.encoder().encode(self) }

    public init(encoded: Data) throws {
        self = try DateCoding.decoder().decode(Self.self, from: encoded)
    }

    private enum CodingKeys: String, CodingKey { case items, session, rest, done, total, generatedAt, day, palette }

    /// A watch app can be older than the iPhone app sending to it, and one value it can't read
    /// mustn't stop it updating: a goal it can't read is left out, and a timer or break it can't
    /// read isn't shown, rather than the whole snapshot failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeLossy(.items)
        session = try? c.decodeIfPresent(FocusSession.self, forKey: .session)
        rest = try? c.decodeIfPresent(RestPeriod.self, forKey: .rest)
        done = try c.decode(.done, default: 0)
        total = try c.decode(.total, default: 0)
        let generated = try c.decode(.generatedAt, default: Date.distantPast)
        generatedAt = generated
        day = (try? c.decodeIfPresent(DayID.self, forKey: .day)) ?? DayID(generated)
        palette = try? c.decodeIfPresent(WatchPalette.self, forKey: .palette)
    }
}

extension WatchSnapshot.Item {
    /// A goal from an iPhone app of any version, written here rather than in the type so the
    /// memberwise initializer stays. A color this version doesn't know draws blue, as in the data
    /// file. A kind it doesn't know is shown as a count: the watch then offers the action the
    /// iPhone named for it, and the iPhone carries it out knowing the goal.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(.name, default: "")
        let decodedKind = (try? c.decode(.kind, default: GoalKind.count)) ?? .count
        kind = decodedKind
        symbol = try c.decode(.symbol, default: SymbolCatalog.defaultSymbol(for: decodedKind))
        color = (try? c.decode(.color, default: .blue)) ?? .blue
        progress = try c.decode(.progress, default: 0)
        progressText = try c.decode(.progressText, default: "")
        streak = try c.decode(.streak, default: 0)
        streakUnit = try c.decode(.streakUnit, default: "day")
        isComplete = try c.decode(.isComplete, default: false)
        actionTitle = try c.decodeIfPresent(String.self, forKey: .actionTitle)
        targetText = try c.decode(.targetText, default: "")
        periodEnd = try c.decodeIfPresent(Date.self, forKey: .periodEnd)
        doneText = try c.decode(.doneText, default: "Done")
        challengeDay = try c.decodeIfPresent(Int.self, forKey: .challengeDay)
        challengeLength = try c.decodeIfPresent(Int.self, forKey: .challengeLength)
    }
}

/// The palette the watch draws in: the iPhone's active palette as it looks in dark mode, the
/// watch's only appearance, so a goal has the same color on the wrist as on the phone.
public struct WatchPalette: Codable, Equatable, Sendable {
    public var accent: OKLCH
    /// One per `GoalColor`, in `GoalColor.allCases` order.
    public var swatches: [OKLCH]

    public init(_ palette: Palette) {
        accent = Self.rounded(palette.dark.accent)
        swatches = palette.dark.swatches.map(Self.rounded)
    }

    /// The default palette, for a snapshot from an iPhone that doesn't send one.
    public static var standard: WatchPalette { WatchPalette(.standard) }

    public func swatch(_ color: GoalColor) -> OKLCH {
        swatches.indices.contains(color.index) ? swatches[color.index] : Self.standard.swatches[color.index]
    }

    private enum CodingKeys: String, CodingKey { case accent, swatches }

    /// Never fails the snapshot it comes in: whatever can't be read is the default palette's.
    public init(from decoder: Decoder) throws {
        let fallback = Self.standard
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        accent = (try? c?.decode(OKLCH.self, forKey: .accent)) ?? fallback.accent
        let sent = (try? c?.decode([OKLCH].self, forKey: .swatches)) ?? []
        swatches = GoalColor.allCases.indices.map { $0 < sent.count ? sent[$0] : fallback.swatches[$0] }
    }

    /// What's worth sending: four decimals of lightness and chroma, two of hue. Rounded here
    /// rather than when written, so a snapshot reads back exactly as it was made.
    private static func rounded(_ color: OKLCH) -> OKLCH {
        OKLCH((color.lightness * 10_000).rounded() / 10_000, (color.chroma * 10_000).rounded() / 10_000,
              Hue.normalized((color.hue * 100).rounded() / 100))
    }
}

/// The keys of the messages between the iPhone and the watch.
public enum WatchMessageKey {
    /// An encoded `WatchSnapshot`, in the application context and in replies.
    public static let snapshot = "snapshot"
    /// An encoded `WatchAction`.
    public static let action = "action"
    /// Asks for a fresh snapshot.
    public static let refresh = "refresh"
}

/// Something done on the watch, carried out on the iPhone. Each says exactly what was tapped,
/// against what the watch showed, so a late or repeated delivery can't undo it: a Stop for a
/// session that already ended does nothing, where a toggle would start it again.
public enum WatchAction: Codable, Equatable, Sendable {
    case start(goal: UUID)
    /// Stops the session on `goal` that started at `sessionStart`, if it's still running.
    case stop(goal: UUID, sessionStart: Date)
    case setPaused(goal: UUID, sessionStart: Date, paused: Bool)
    case quickAdd(goal: UUID)
    /// Ends the break that started at `restStart` and starts the next block.
    case startNextBlock(restStart: Date)
    case endRest(restStart: Date)
}

/// An action with when it was tapped, and an id so it's carried out once however often it
/// arrives (a reply lost on the way back gets it sent again).
public struct WatchCommand: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var action: WatchAction
    public var date: Date

    public init(id: UUID = UUID(), action: WatchAction, date: Date = .now) {
        self.id = id
        self.action = action
        self.date = date
    }

    public func encoded() throws -> Data { try DateCoding.encoder().encode(self) }

    public init(encoded: Data) throws {
        self = try DateCoding.decoder().decode(Self.self, from: encoded)
    }
}

extension ProgressEngine {
    public func watchSnapshot(now: Date) -> WatchSnapshot {
        let today = stackOrdered(todayGoals(now: now))
        var items = today.prefix(WatchSnapshot.itemLimit).map { item(for: $0, now: now) }
        // A running timer's goal always makes the list, even when Today wouldn't show it.
        if let session = data.session, !items.contains(where: { $0.id == session.goalID }), let goal = goal(session.goalID) {
            items.insert(item(for: goal, now: now), at: 0)
        }
        let summary = todaySummary(now: now)
        return WatchSnapshot(items: items, session: data.session, rest: data.rest, done: summary.done, total: summary.total,
                             generatedAt: now, day: DayID(now, calendar: calendar), palette: WatchPalette(data.preferences.activePalette))
    }

    private func item(for goal: Goal, now: Date) -> WatchSnapshot.Item {
        let streak = streak(for: goal, now: now)
        let challenge = challengeStatus(for: goal, now: now).flatMap { $0.isFinished || $0.dayNumber == 0 ? nil : $0 }
        return WatchSnapshot.Item(
            id: goal.id, name: goal.name, symbol: goal.symbol, color: goal.color, kind: goal.kind,
            progress: progress(for: goal, now: now),
            progressText: goal.kind == .milestones
                ? "\(goal.milestones.count(where: \.isDone)) / \(goal.milestones.count) milestones"
                : goal.progressText(currentAmount(for: goal, now: now), target: target(for: goal)),
            streak: streak.current, streakUnit: streak.unit, isComplete: isComplete(goal, now: now),
            actionTitle: actionTitle(for: goal),
            targetText: goal.kind == .milestones ? "\(goal.milestones.count) milestones" : goal.format(target(for: goal)),
            periodEnd: goal.effectivePeriod == .total ? nil : interval(of: goal.effectivePeriod, containing: now).end,
            doneText: Self.doneText(for: goal),
            challengeDay: challenge?.dayNumber, challengeLength: challenge?.challenge.days)
    }

    private static func doneText(for goal: Goal) -> String {
        if goal.kind == .milestones { return "All done" }
        return switch goal.effectivePeriod {
        case .daily: "Done for today"
        case .weekly: "Done this week"
        case .monthly: "Done this month"
        case .yearly: "Done this year"
        case .total: "Target reached"
        }
    }

    private func actionTitle(for goal: Goal) -> String? {
        switch goal.kind {
        case .time: nil
        case .count, .amount: goal.kind == .count && goal.quickAddStep == 1 ? "+1" : "+\(goal.format(goal.quickAddStep))"
        case .milestones: goal.milestones.contains { !$0.isDone } ? "Done" : nil
        case .books: goal.currentBook == nil ? nil : "+\(Formatting.number(goal.quickAddStep)) pages"
        }
    }
}

extension AppData {
    /// Carries out a command from the watch, dated when it was tapped (never later than `now`),
    /// so a Stop delivered hours late doesn't count the hours in between.
    public mutating func apply(_ command: WatchCommand, now: Date = .now, calendar: Calendar = .current) {
        let tapped = min(command.date, now)
        func isShown(_ goal: UUID, _ start: Date) -> Bool {
            guard let session, session.goalID == goal else { return false }
            return abs(session.startedAt.timeIntervalSince(start)) < 0.001
        }
        func isShownRest(_ start: Date) -> Bool {
            guard let rest else { return false }
            return abs(rest.start.timeIntervalSince(start)) < 0.001
        }
        // The timer's last change on any device: a tap from before it can't reach back past it.
        let lastTimerChange = sync.stamp(SyncState.session)
        switch command.action {
        case .start(let goal):
            guard let target = self.goal(goal), target.kind == .time, !target.isArchived, session?.goalID != goal else { return }
            let start = max(tapped, lastTimerChange, session?.startedAt ?? tapped)
            startFocus(on: goal, planned: defaultFocusLength(for: goal), at: min(start, now), calendar: calendar)
        case .stop(let goal, let start):
            guard isShown(goal, start) else { return }
            stopFocus(at: max(tapped, start), calendar: calendar)
        case .setPaused(let goal, let start, let paused):
            guard isShown(goal, start), let current = session, current.isRunning == paused else { return }
            if paused {
                pauseFocus(at: max(tapped, current.runningSince ?? tapped))
            } else {
                resumeFocus(at: min(max(tapped, current.segments.last?.end ?? tapped), now))
            }
        case .quickAdd(let goal):
            quickAdd(to: goal, at: tapped)
        case .startNextBlock(let restStart):
            guard isShownRest(restStart) else { return }
            startNextBlock(at: max(tapped, restStart), calendar: calendar)
        case .endRest(let restStart):
            guard isShownRest(restStart) else { return }
            endRest()
        }
    }
}
