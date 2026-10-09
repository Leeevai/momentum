import Foundation

/// Calendar arithmetic on plain day numbers, for the hot paths where `Calendar` is too slow.
/// Days count from 1 January 1970 in local time; dates are proleptic Gregorian.
enum DayMath {
    /// The local day number `date` falls on in `timeZone`.
    static func localDay(_ date: Date, _ timeZone: TimeZone) -> Int {
        let seconds = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        return Int((seconds / 86_400).rounded(.down))
    }

    /// The hour of day `date` falls in, in `timeZone`.
    static func localHour(_ date: Date, _ timeZone: TimeZone) -> Int {
        let seconds = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        let intoDay = seconds - (seconds / 86_400).rounded(.down) * 86_400
        return min(23, Int(intoDay / 3600))
    }

    /// Year, month and day of a day number (Howard Hinnant's civil_from_days).
    static func civil(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// The day number of a year, month and day (days_from_civil).
    static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The day number of a yyyymmdd day key.
    static func days(fromKey key: Int) -> Int {
        days(year: key / 10_000, month: key / 100 % 100, day: key % 100)
    }

    /// 1 for Sunday through 7 for Saturday, as `Calendar` numbers weekdays.
    static func weekday(_ days: Int) -> Int {
        // 1 January 1970 was a Thursday.
        ((days + 4) % 7 + 7) % 7 + 1
    }
}
