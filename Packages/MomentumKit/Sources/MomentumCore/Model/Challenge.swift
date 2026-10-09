import Foundation

/// A fixed run of days to keep a goal going, like "30 days of reading": every day it's due, from
/// `start`, for `days` days. A day off or a break doesn't count against it.
public struct Challenge: Codable, Hashable, Sendable {
    /// The first day.
    public var start: DayID
    public var days: Int

    /// The lengths offered: a week up to the hundred-day classic, with 66 (the average time to
    /// form a habit, by a well-known study) and 75 in between.
    public static let lengths = [7, 14, 21, 30, 66, 75, 100]

    public init(start: DayID, days: Int) {
        self.start = start
        self.days = max(1, days)
    }

    /// "30-day challenge".
    public var title: String { "\(days)-day challenge" }
}
