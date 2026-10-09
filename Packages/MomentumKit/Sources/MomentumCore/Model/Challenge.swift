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

    /// The longest a challenge can be, so a damaged file can't ask for millions of days.
    public static let maximumDays = 1000

    public init(start: DayID, days: Int) {
        self.start = start
        self.days = min(max(1, days), Self.maximumDays)
    }

    private enum CodingKeys: String, CodingKey { case start, days }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(start: try c.decode(DayID.self, forKey: .start), days: try c.decode(Int.self, forKey: .days))
    }

    /// "30-day challenge".
    public var title: String { "\(days)-day challenge" }
}

extension Goal {
    /// Challenges suit goals with something to do each day: daily goals, and reading.
    public var supportsChallenge: Bool {
        effectivePeriod == .daily || kind == .books
    }
}
