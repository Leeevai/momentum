import Foundation

public enum Formatting {
    /// A whole number from any double: anything not a number reads as zero and anything out of
    /// range is held at the edge, where `Int(_:)` would stop the app.
    static func whole(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value, -1e15), 1e15))
    }

    /// "45m", "1h 30m", "2h"; seconds under a minute read as "<1m" unless zero.
    public static func duration(_ seconds: Double) -> String {
        let totalMinutes = whole((seconds / 60).rounded(.down))
        if totalMinutes == 0 { return seconds > 0 ? "<1m" : "0m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    /// A stopwatch reading: "4:07" or "1:02:09".
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, whole(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// "1,250" or "12.5", trimming a trailing ".0". From 100 up, decimals are noise and are dropped.
    public static func number(_ value: Double) -> String {
        abs(value) >= 100
            ? value.formatted(.number.precision(.fractionLength(0)))
            : value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Picks the singular of a plural unit for a value of one: "pages" -> "page".
    public static func unit(_ unit: String, for value: Double) -> String {
        guard abs(value - 1) < 0.0001, unit.count > 2 else { return unit }
        let lower = unit.lowercased()
        if lower.hasSuffix("ies") { return String(unit.dropLast(3)) + "y" }
        if lower.hasSuffix("sses") || lower.hasSuffix("ches") || lower.hasSuffix("shes") || lower.hasSuffix("xes") {
            return String(unit.dropLast(2))
        }
        if lower.hasSuffix("s") && !lower.hasSuffix("ss") { return String(unit.dropLast()) }
        return unit
    }

    public static func percent(_ rate: Double?) -> String {
        guard let rate else { return "–" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }
}

extension Goal {
    /// The unit shown after numbers; time goals format as durations instead.
    public var displayUnit: String {
        switch kind {
        case .time: ""
        case .count: unit.isEmpty ? "times" : unit
        case .amount: unit
        case .milestones: "milestones"
        case .books: "books"
        }
    }

    /// A value with its unit: "1h 30m", "3 workouts", "12.5 km", "2 books".
    public func format(_ value: Double) -> String {
        if kind == .time { return Formatting.duration(value) }
        let unit = Formatting.unit(displayUnit, for: value)
        return unit.isEmpty ? Formatting.number(value) : "\(Formatting.number(value)) \(unit)"
    }

    /// What log entries add up to: the goal's own unit, except for books goals, whose entries
    /// are pages read ("120 pages") while the target counts books.
    public func formatLogged(_ amount: Double) -> String {
        guard kind == .books else { return format(amount) }
        return "\(Formatting.number(amount)) \(Formatting.unit("pages", for: amount))"
    }

    /// A bare value for tight spaces: "1h 30m", "3", "12.5".
    public func formatShort(_ value: Double) -> String {
        kind == .time ? Formatting.duration(value) : Formatting.number(value)
    }

    /// A value against a target: "45m / 1h 30m", "2 / 4 workouts", "3 / 24 books".
    public func progressText(_ value: Double, target: Double) -> String {
        if kind == .time { return "\(Formatting.duration(value)) / \(Formatting.duration(target))" }
        let unit = displayUnit
        let numbers = "\(Formatting.number(value)) / \(Formatting.number(target))"
        return unit.isEmpty ? numbers : "\(numbers) \(unit)"
    }

    /// "1h 30m a day", "4 workouts a week", "24 books a year", "50,000 words by Dec 31".
    public var targetDescription: String {
        switch kind {
        case .milestones:
            let count = milestones.count
            return count == 0 ? "No milestones yet" : "\(count) \(Formatting.unit("milestones", for: Double(count)))"
        case .time, .count, .amount, .books:
            let amount = format(target)
            switch period {
            case .total:
                if let deadline { return "\(amount) by \(deadline.formatted(.dateTime.month(.abbreviated).day().year()))" }
                return "\(amount) overall"
            default:
                return "\(amount) a \(period.noun)"
            }
        }
    }

    /// When a daily goal is due, or the cadence for others: "Weekdays", "Mon, Wed, Fri", "Weekly".
    public func scheduleDescription(calendar: Calendar = .current) -> String {
        guard effectivePeriod == .daily else {
            return kind == .milestones ? "Project" : period.title
        }
        if weekdays.count == 7 { return "Every day" }
        if weekdays == Set(2...6) { return "Weekdays" }
        if weekdays == [1, 7] { return "Weekends" }
        let symbols = calendar.shortWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return order.filter(weekdays.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
    }

    /// A rate of progress: per day for most goals, per month for books, which move slowly.
    public func rateText(perDay: Double) -> String {
        if kind == .books {
            let perMonth = perDay * 30
            return "\(Formatting.number(perMonth)) \(Formatting.unit("books", for: perMonth)) a month"
        }
        return "\(format(perDay)) a day"
    }

    /// "12-day streak", "3-week streak".
    public static func streakText(_ count: Int, unit: String) -> String {
        "\(count)-\(unit) streak"
    }
}
