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
        let updated = SharedStore.update { data in
            switch stored.kind {
            case .time:
                data.log((amount ?? stored.quickAddStep / 60) * 60, for: stored.id)
            case .books:
                if let book = stored.currentBook {
                    data.logPages(Int(amount ?? stored.quickAddStep), in: book.id, of: stored.id)
                }
            case .milestones:
                data.completeNextMilestone(in: stored.id)
            case .count, .amount:
                data.log(amount ?? stored.quickAddStep, for: stored.id)
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
        let rest = remaining.isEmpty ? "Everything is done. 🎉" : "Still to do: \(remaining.formatted(.list(type: .and)))."
        return .result(value: summary.done, dialog: "\(summary.done) of \(summary.total) goals done today, best streak \(streak). \(rest)")
    }
}

enum MomentumIntentError: Error, CustomLocalizedStringResourceConvertible {
    case goalNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .goalNotFound: "That goal no longer exists."
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
    }
}
