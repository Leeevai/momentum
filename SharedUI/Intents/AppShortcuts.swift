import AppIntents
import MomentumCore

/// "Start focusing on Deep work" in Shortcuts, Spotlight and Siri.
struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Session"
    static let description = IntentDescription("Starts a Momentum focus timer for a goal.")

    @Parameter(title: "Goal")
    var goal: GoalEntity

    @Parameter(title: "Minutes", description: "Leave empty to use the goal's default length.", inclusiveRange: (1, 600))
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Focus on \(\.$goal) for \(\.$minutes) minutes")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = SharedStore.load()
        guard let stored = data.goal(goal.id) else { throw MomentumIntentError.goalNotFound }
        guard stored.kind == .time else { throw MomentumIntentError.notATimeGoal(stored.name) }
        let length = minutes ?? stored.focusMinutes ?? data.preferences.defaultFocusMinutes
        SharedStore.update { $0.startFocus(on: stored.id, planned: Double(length) * 60) }
        return .result(dialog: "Focusing on \(stored.name) for \(length) minutes.")
    }
}

struct StopFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Focus Session"
    static let description = IntentDescription("Stops the running focus timer and saves the time.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var logged: [LogEntry] = []
        var goalName = ""
        SharedStore.update { data in
            goalName = data.session.flatMap { data.goal($0.goalID)?.name } ?? ""
            logged = data.stopFocus()
        }
        guard !logged.isEmpty else { return .result(dialog: "No focus session is running.") }
        let seconds = logged.reduce(0) { $0 + $1.amount }
        return .result(dialog: "Saved \(Formatting.duration(seconds)) of \(goalName).")
    }
}

struct LogProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Progress"
    static let description = IntentDescription("Logs progress on a goal: minutes for time goals, pages for books, otherwise the goal's unit.")

    @Parameter(title: "Goal")
    var goal: GoalEntity

    @Parameter(title: "Amount", description: "Leave empty to log the goal's quick-add step.")
    var amount: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) on \(\.$goal)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = SharedStore.load()
        guard let stored = data.goal(goal.id) else { throw MomentumIntentError.goalNotFound }
        // Whatever Shortcuts passes in: a day's worth of minutes, or a library's worth of pages, at most.
        func bounded(_ value: Double, _ limit: Double) -> Double {
            value.isFinite ? min(max(value, -limit), limit) : 0
        }
        let updated = SharedStore.update { data in
            switch stored.kind {
            case .time:
                data.log(bounded(amount ?? stored.quickAddStep / 60, 24 * 60) * 60, for: stored.id)
            case .books:
                if let book = stored.currentBook {
                    data.logPages(Int(bounded(amount ?? stored.quickAddStep, 100_000)), in: book.id, of: stored.id)
                }
            case .milestones:
                data.completeNextMilestone(in: stored.id)
            case .count, .amount:
                data.log(bounded(amount ?? stored.quickAddStep, AppData.entryLimit), for: stored.id)
            }
        }
        let engine = ProgressEngine(data: updated)
        guard let goal = engine.goal(stored.id) else { throw MomentumIntentError.goalNotFound }
        let progress = goal.progressText(engine.currentAmount(for: goal, now: .now), target: engine.target(for: goal))
        return .result(dialog: "\(goal.name): \(progress) \(goal.effectivePeriod.currentLabel.lowercased()).")
    }
}

struct CheckProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Today's Progress"
    static let description = IntentDescription("Tells you how many of today's goals are done.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let engine = ProgressEngine(data: SharedStore.load())
        let summary = engine.todaySummary(now: .now)
        let streak = engine.longestCurrentStreak(now: .now)
        let remaining = engine.todayGoals(now: .now).filter { !engine.isComplete($0, now: .now) }.map(\.name)
        let rest = remaining.isEmpty ? "Everything is done. Nice work." : "Still to do: \(remaining.formatted(.list(type: .and)))."
        return .result(value: summary.done, dialog: "\(summary.done) of \(summary.total) goals done today, best streak \(streak). \(rest)")
    }
}

/// How the day felt, for Siri and Shortcuts.
enum MoodChoice: String, AppEnum {
    case rough, low, okay, good, great

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"
    static let caseDisplayRepresentations: [MoodChoice: DisplayRepresentation] = [
        .rough: DisplayRepresentation(title: "Rough", image: .init(systemName: "cloud.bolt.rain.fill")),
        .low: DisplayRepresentation(title: "Low", image: .init(systemName: "cloud.drizzle.fill")),
        .okay: DisplayRepresentation(title: "Okay", image: .init(systemName: "cloud.fill")),
        .good: DisplayRepresentation(title: "Good", image: .init(systemName: "cloud.sun.fill")),
        .great: DisplayRepresentation(title: "Great", image: .init(systemName: "sun.max.fill")),
    ]

    var mood: Mood {
        switch self {
        case .rough: .rough
        case .low: .low
        case .okay: .okay
        case .good: .good
        case .great: .great
        }
    }
}

/// "Log my mood in Momentum": rates today in the journal.
struct LogMoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Mood"
    static let description = IntentDescription("Rates how today feels in the Momentum journal.")

    @Parameter(title: "Mood")
    var mood: MoodChoice

    @Parameter(title: "A win", description: "Something that went well today.")
    var win: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Today felt \(\.$mood)") { \.$win }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let chosen = mood.mood
        let note = win?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        SharedStore.update { data in
            data.updateJournal(for: DayID(.now)) { entry in
                entry.mood = chosen
                if !note.isEmpty { entry.win = note }
            }
        }
        return .result(dialog: "Noted: a \(chosen.title.lowercased()) day.")
    }
}

/// "How was my week in Momentum": the week in review, read aloud.
struct WeekSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Week in Review"
    static let description = IntentDescription("Sums up the last seven days: focus, perfect days and wins.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let review = ProgressEngine(data: SharedStore.load()).weekReview(endingAt: .now)
        var parts = ["\(Formatting.duration(review.focusSeconds)) of focus"]
        if let change = review.focusChange {
            parts[0] += change >= 0 ? ", up \(Formatting.percent(change))" : ", down \(Formatting.percent(-change))"
        }
        parts.append("\(review.perfectDays) perfect \(review.perfectDays == 1 ? "day" : "days")")
        if let win = review.wins.last { parts.append("and a win: \(win.text)") }
        return .result(dialog: "This week: \(parts.joined(separator: ", ")).")
    }
}

/// "How's my challenge going in Momentum": the day, what's left, and any misses.
struct ChallengeStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Challenge Status"
    static let description = IntentDescription("Says which day of a goal's challenge it is and how it's going.")

    @Parameter(title: "Goal", description: "Leave empty for the first goal with a challenge.")
    var goal: GoalEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = ProgressEngine(data: SharedStore.load())
        let now = Date()
        let chosen = goal.flatMap { engine.goal($0.id) } ?? engine.activeGoals.first { $0.challenge != nil }
        guard let chosen, let status = engine.challengeStatus(for: chosen, now: now) else {
            return .result(dialog: "No challenge is running. Start one from a goal's page.")
        }
        let days = status.challenge.days
        if status.dayNumber == 0 {
            return .result(dialog: "\(chosen.name): your \(days)-day challenge starts soon.")
        }
        if status.isWon {
            return .result(dialog: "\(chosen.name): all \(days) days kept. Challenge complete!")
        }
        if status.isFinished {
            return .result(dialog: "\(chosen.name): finished with \(status.kept) of \(days) days kept.")
        }
        let misses = status.missed == 0 ? "no misses yet" : "\(status.missed) missed"
        let today = status.days.contains(.today) ? " Today still needs doing." : " Today's done."
        return .result(dialog: "\(chosen.name): day \(status.dayNumber) of \(days), \(status.remaining) to go, \(misses).\(today)")
    }
}

enum MomentumIntentError: Error, CustomLocalizedStringResourceConvertible {
    case goalNotFound
    case notATimeGoal(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .goalNotFound: "That goal no longer exists."
        case .notATimeGoal(let name): "\(name) isn't tracked by time. Use Log Progress for it instead."
        }
    }
}

struct MomentumShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(), phrases: [
            "Start focusing in \(.applicationName)",
            "Focus on \(\.$goal) in \(.applicationName)",
        ], shortTitle: "Start Focus", systemImageName: "timer")
        AppShortcut(intent: StopFocusIntent(), phrases: [
            "Stop focusing in \(.applicationName)",
        ], shortTitle: "Stop Focus", systemImageName: "stop.circle")
        AppShortcut(intent: LogProgressIntent(), phrases: [
            "Log progress in \(.applicationName)",
            "Log \(\.$goal) in \(.applicationName)",
        ], shortTitle: "Log Progress", systemImageName: "plus.circle")
        AppShortcut(intent: CheckProgressIntent(), phrases: [
            "How am I doing in \(.applicationName)",
            "Check my progress in \(.applicationName)",
        ], shortTitle: "Today's Progress", systemImageName: "chart.pie")
        AppShortcut(intent: LogMoodIntent(), phrases: [
            "Log my mood in \(.applicationName)",
            "Today felt \(\.$mood) in \(.applicationName)",
        ], shortTitle: "Log Mood", systemImageName: "cloud.sun")
        AppShortcut(intent: ChallengeStatusIntent(), phrases: [
            "How's my challenge going in \(.applicationName)",
            "Check my challenge in \(.applicationName)",
        ], shortTitle: "Challenge Status", systemImageName: "flag.2.crossed")
        AppShortcut(intent: WeekSummaryIntent(), phrases: [
            "How was my week in \(.applicationName)",
            "Review my week in \(.applicationName)",
        ], shortTitle: "Week in Review", systemImageName: "calendar.badge.checkmark")
    }
}
