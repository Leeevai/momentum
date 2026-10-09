import Foundation

/// A timely, specific nudge: a streak about to break, the next habit in a stack, a target that's
/// become too easy. Built from the same history as everything else, so it needs no setup.
public struct CoachTip: Identifiable, Hashable, Sendable {
    public enum Action: Hashable, Sendable {
        case startFocus(UUID)
        case log(UUID)
        case open(UUID)
        case setTarget(UUID, Double)
        case planDay
        case reflect
    }

    public enum Tone: Sendable {
        /// Something is about to slip.
        case urgent
        /// Good news, or a step up.
        case positive
        case neutral
    }

    public let id: String
    public let goalID: UUID?
    public let symbol: String
    public let title: String
    public let message: String
    public let action: Action?
    public let actionTitle: String?
    public let tone: Tone
    public let priority: Int
}

extension ProgressEngine {
    /// The most useful tips right now, most important first.
    public func coachTips(now: Date, limit: Int = 4) -> [CoachTip] {
        var tips: [CoachTip] = []
        let hour = calendar.component(.hour, from: now)
        let goals = activeGoals.filter { !$0.isOnBreak(at: now) }
        let today = DayID(now, calendar: calendar)
        let journal = data.journalEntry(for: today)

        for goal in goals {
            if let tip = streakAtRisk(goal, hour: hour, now: now) { tips.append(tip) }
            if let tip = nextInStack(goal, now: now) { tips.append(tip) }
            if let tip = behindPace(goal, now: now) { tips.append(tip) }
            if let tip = bestTime(goal, hour: hour, now: now) { tips.append(tip) }
            if let tip = targetAdjustment(goal, now: now) { tips.append(tip) }
            if let tip = neglected(goal, now: now) { tips.append(tip) }
            tips.append(contentsOf: almostFinishedBooks(goal))
            tips.append(contentsOf: dueMilestones(goal, now: now))
        }
        if data.preferences.journalPromptsEnabled {
            if (5..<12).contains(hour), journal?.hasPlan != true, !goals.isEmpty {
                tips.append(CoachTip(id: "plan-\(today)", goalID: nil, symbol: "sun.horizon.fill", title: "Plan your day",
                                     message: "Pick up to three priorities and set an intention. It takes a minute.",
                                     action: .planDay, actionTitle: "Plan", tone: .neutral, priority: 25))
            }
            if hour >= 19, journal?.hasReflection != true {
                tips.append(CoachTip(id: "reflect-\(today)", goalID: nil, symbol: "moon.stars.fill", title: "How did today go?",
                                     message: "Note your mood, energy and one win. Insights will show what your best days have in common.",
                                     action: .reflect, actionTitle: "Reflect", tone: .neutral, priority: 25))
            }
        }
        return Array(tips.sorted { ($0.priority, $0.id) > ($1.priority, $1.id) }.prefix(limit))
    }

    // MARK: - Tips

    private func streakAtRisk(_ goal: Goal, hour: Int, now: Date) -> CoachTip? {
        guard hour >= 17, goal.effectivePeriod == .daily, goal.kind != .milestones, goal.kind != .books,
              isRequired(goal, on: now), !keepsStreak(goal, periodContaining: now, now: now) else { return nil }
        let streak = streak(for: goal, now: now)
        guard streak.current >= 2 else { return nil }
        let missing = max(0, streakThreshold(for: goal) - amount(for: goal, on: now, now: now))
        let keeps = goal.streakMinimum != nil ? "Just \(goal.format(missing)) keeps it alive." : "\(goal.format(missing)) to go before midnight."
        return CoachTip(id: "risk-\(goal.id)", goalID: goal.id, symbol: "flame.fill",
                        title: "Keep your \(streak.current)-day \(goal.name) streak", message: keeps,
                        action: primaryAction(for: goal), actionTitle: goal.kind == .time ? "Start" : "Log", tone: .urgent, priority: 100)
    }

    private func nextInStack(_ goal: Goal, now: Date) -> CoachTip? {
        guard let anchorID = goal.stackAfter, let anchor = self.goal(anchorID), !anchor.isArchived,
              isComplete(anchor, now: now), !isComplete(goal, now: now), isScheduled(goal, on: now) else { return nil }
        return CoachTip(id: "stack-\(goal.id)", goalID: goal.id, symbol: "square.stack.3d.up.fill",
                        title: "Next up: \(goal.name)", message: "\(anchor.name) is done, and \(goal.name) is stacked right after it.",
                        action: primaryAction(for: goal), actionTitle: goal.kind == .time ? "Start" : "Log", tone: .positive, priority: 90)
    }

    private func behindPace(_ goal: Goal, now: Date) -> CoachTip? {
        guard let pace = pace(for: goal, now: now), pace.status == .behind, let needed = pace.neededPerDay,
              let deadline = pace.deadline else { return nil }
        let due = deadline.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day())
        return CoachTip(id: "pace-\(goal.id)", goalID: goal.id, symbol: "gauge.with.dots.needle.33percent",
                        title: "\(goal.name) is falling behind", message: "\(goal.rateText(perDay: needed)) gets you there by \(due).",
                        action: .open(goal.id), actionTitle: "Open", tone: .urgent, priority: 60)
    }

    private func bestTime(_ goal: Goal, hour: Int, now: Date) -> CoachTip? {
        guard goal.kind == .time, !isComplete(goal, now: now), isScheduled(goal, on: now),
              let peak = peakHour(for: goal, now: now), hour == peak || hour == peak - 1 else { return nil }
        let time = calendar.date(bySettingHour: peak, minute: 0, second: 0, of: now)?.formatted(date: .omitted, time: .shortened) ?? "\(peak):00"
        return CoachTip(id: "time-\(goal.id)", goalID: goal.id, symbol: "clock.fill", title: "Your \(goal.name) hour",
                        message: "You usually focus on \(goal.name) around \(time). Now is a good time.",
                        action: .startFocus(goal.id), actionTitle: "Start", tone: .positive, priority: 50)
    }

    /// Suggests a bigger target after a run of easy wins, or a smaller one after weeks of misses.
    private func targetAdjustment(_ goal: Goal, now: Date) -> CoachTip? {
        guard goal.effectivePeriod == .daily, goal.kind == .time || goal.kind == .count || goal.kind == .amount,
              let record = recentRecord(goal, days: 21, now: now), record.due >= 12 else { return nil }
        let rate = Double(record.met) / Double(record.due)
        if rate >= 0.9 {
            let raised = goal.suggestedTarget(raising: true)
            guard raised > goal.target else { return nil }
            return CoachTip(id: "raise-\(goal.id)", goalID: goal.id, symbol: "arrow.up.forward.circle.fill", title: "Ready for more?",
                            message: "You hit \(goal.name) on \(record.met) of the last \(record.due) days. Try \(goal.format(raised)) a day?",
                            action: .setTarget(goal.id, raised), actionTitle: "Raise", tone: .positive, priority: 35)
        }
        if rate <= 0.25, now.timeIntervalSince(goal.createdAt) >= 21 * 86_400 {
            let lowered = goal.suggestedTarget(raising: false)
            guard lowered < goal.target else { return nil }
            return CoachTip(id: "lower-\(goal.id)", goalID: goal.id, symbol: "arrow.down.forward.circle.fill", title: "Make \(goal.name) easier to start",
                            message: "It's been hit on \(record.met) of the last \(record.due) days. \(goal.format(lowered)) a day keeps the habit alive.",
                            action: .setTarget(goal.id, lowered), actionTitle: "Adjust", tone: .neutral, priority: 34)
        }
        return nil
    }

    private func neglected(_ goal: Goal, now: Date) -> CoachTip? {
        guard goal.effectivePeriod != .daily, !isComplete(goal, now: now),
              now.timeIntervalSince(goal.createdAt) >= 10 * 86_400 else { return nil }
        let last = lastActivity(of: goal) ?? goal.createdAt
        let days = calendar.dateComponents([.day], from: startOfDay(last), to: startOfDay(now)).day ?? 0
        guard days >= 10 else { return nil }
        return CoachTip(id: "idle-\(goal.id)", goalID: goal.id, symbol: "hourglass.bottomhalf.filled",
                        title: "\(days) days since \(goal.name)", message: "A few minutes today gets it moving again.",
                        action: primaryAction(for: goal), actionTitle: goal.kind == .time ? "Start" : "Open", tone: .neutral, priority: 30)
    }

    private func almostFinishedBooks(_ goal: Goal) -> [CoachTip] {
        guard goal.kind == .books else { return [] }
        return goal.books.compactMap { book in
            guard book.status == .reading, let total = book.totalPages else { return nil }
            let left = total - book.currentPage
            guard left > 0, left <= 30 else { return nil }
            return CoachTip(id: "book-\(book.id)", goalID: goal.id, symbol: "book.fill", title: "Almost done with \(book.title)",
                            message: "Just \(left) \(left == 1 ? "page" : "pages") left.", action: .open(goal.id), actionTitle: "Open",
                            tone: .positive, priority: 45)
        }
    }

    private func dueMilestones(_ goal: Goal, now: Date) -> [CoachTip] {
        let today = startOfDay(now)
        return goal.milestones.compactMap { milestone in
            guard !milestone.isDone, let due = milestone.dueDate, startOfDay(due) <= today else { return nil }
            let overdue = startOfDay(due) < today
            let message = overdue
                ? "Overdue since \(due.formatted(.dateTime.month(.abbreviated).day())), in \(goal.name)."
                : "Due today, in \(goal.name)."
            return CoachTip(id: "milestone-\(milestone.id)", goalID: goal.id, symbol: overdue ? "exclamationmark.circle.fill" : "flag.fill",
                            title: milestone.title, message: message, action: .open(goal.id), actionTitle: "Open",
                            tone: overdue ? .urgent : .neutral, priority: overdue ? 75 : 70)
        }
    }

    // MARK: - Helpers

    private func primaryAction(for goal: Goal) -> CoachTip.Action {
        switch goal.kind {
        case .time: .startFocus(goal.id)
        case .count, .amount: .log(goal.id)
        case .milestones, .books: .open(goal.id)
        }
    }

    /// Due and met days over the last `days` days, not counting today.
    func recentRecord(_ goal: Goal, days: Int, now: Date) -> (due: Int, met: Int)? {
        let first = startOfDay(firstDay(of: goal))
        var due = 0
        var met = 0
        for offset in 1...days {
            let day = self.day(-offset, from: now)
            guard day >= first else { break }
            guard isRequired(goal, on: day) else { continue }
            due += 1
            if isMet(goal, periodContaining: day, now: now) { met += 1 }
        }
        return due == 0 ? nil : (due, met)
    }

    /// The hour of day most of a goal's recent progress started in, given enough history.
    func peakHour(for goal: Goal, now: Date) -> Int? {
        let since = day(-60, from: now)
        let recent = entries(for: goal).filter { $0.date >= since && $0.amount > 0 }
        guard recent.count >= 8 else { return nil }
        var byHour = [Double](repeating: 0, count: 24)
        for entry in recent {
            byHour[calendar.component(.hour, from: entry.date)] += goal.kind == .time ? entry.amount : 1
        }
        guard let peak = byHour.indices.max(by: { byHour[$0] < byHour[$1] }), byHour[peak] > 0 else { return nil }
        return peak
    }

    private func lastActivity(of goal: Goal) -> Date? {
        let logged = entries(for: goal).filter { $0.amount > 0 }.map(\.date).max()
        let finished = (goal.milestones.compactMap(\.completedAt) + goal.books.compactMap(\.finishedAt)).max()
        return [logged, finished].compactMap { $0 }.max()
    }
}

extension Goal {
    /// A round step up or down from the current target, for target suggestions.
    public func suggestedTarget(raising: Bool) -> Double {
        switch kind {
        case .time:
            let minutes = target / 60
            if raising {
                let step: Double = minutes < 30 ? 5 : minutes <= 120 ? 15 : 30
                return (minutes + step) * 60
            }
            return max(5, (minutes * 0.6 / 5).rounded(.down) * 5) * 60
        case .count:
            return raising ? target + 1 : max(1, (target * 0.6).rounded(.down))
        case .amount, .books:
            let step = max(quickAddStep, 1)
            let scaled = raising ? target * 1.1 : target * 0.6
            let rounded = ((scaled / step).rounded(raising ? .up : .down)) * step
            return raising ? max(rounded, target + step) : max(step, min(rounded, target - step))
        case .milestones:
            return target
        }
    }
}
