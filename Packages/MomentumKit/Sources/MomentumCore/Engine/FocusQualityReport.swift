import Foundation

/// How rated focus sessions went over a stretch of time, and when they go best.
public struct FocusQualityReport: Equatable, Sendable {
    /// Rated focus time, in seconds, by how it went.
    public var seconds: [FocusQuality: Double]
    /// Rated sessions (a session across midnight counts once per day).
    public var ratedSessions: Int
    /// The hour of the day (0 to 23) whose sessions go best, once there are enough to say.
    public var bestHour: Int?

    public var ratedSeconds: Double { seconds.values.reduce(0, +) }

    /// The share of rated time spent in flow.
    public var flowShare: Double? {
        ratedSeconds > 0 ? (seconds[.flow] ?? 0) / ratedSeconds : nil
    }

    /// Sessions needed in an hour before it can be the best one.
    public static let sessionsForBestHour = 3
}

extension ProgressEngine {
    /// Rated focus sessions in `interval`.
    public func focusQualityReport(in interval: DateInterval) -> FocusQualityReport {
        var seconds: [FocusQuality: Double] = [:]
        var sessions = 0
        // Per hour: rated sessions, and their quality weighted by length.
        var hours: [Int: (count: Int, weighted: Double, seconds: Double)] = [:]
        for entry in data.entries where entry.amount > 0 {
            guard let quality = entry.quality, interval.contains(entry.date) else { continue }
            seconds[quality, default: 0] += entry.amount
            sessions += 1
            let hour = DayMath.localHour(entry.date, calendar.timeZone)
            let current = hours[hour] ?? (0, 0, 0)
            hours[hour] = (current.count + 1, current.weighted + Double(quality.rawValue) * entry.amount, current.seconds + entry.amount)
        }
        let best = hours
            .filter { $0.value.count >= FocusQualityReport.sessionsForBestHour && $0.value.seconds > 0 }
            .max { lhs, rhs in
                let left = lhs.value.weighted / lhs.value.seconds, right = rhs.value.weighted / rhs.value.seconds
                return left != right ? left < right : (lhs.value.seconds, rhs.key) < (rhs.value.seconds, lhs.key)
            }?.key
        return FocusQualityReport(seconds: seconds, ratedSessions: sessions, bestHour: best)
    }
}

extension AppData {
    /// Rates the entries a session logged; nil clears the rating.
    public mutating func rateSession(_ entryIDs: Set<UUID>, quality: FocusQuality?) {
        for index in entries.indices where entryIDs.contains(entries[index].id) {
            entries[index].quality = quality
        }
    }
}
