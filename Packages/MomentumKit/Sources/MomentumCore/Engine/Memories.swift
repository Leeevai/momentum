import Foundation

/// A journal entry from the same date some time back: "a year ago today".
public struct JournalMemory: Equatable, Identifiable, Sendable {
    public enum Span: Int, CaseIterable, Sendable {
        case week, month, year, twoYears

        public var title: String {
            switch self {
            case .week: "A week ago"
            case .month: "A month ago"
            case .year: "A year ago"
            case .twoYears: "Two years ago"
            }
        }

        var components: DateComponents {
            switch self {
            case .week: DateComponents(day: -7)
            case .month: DateComponents(month: -1)
            case .year: DateComponents(year: -1)
            case .twoYears: DateComponents(year: -2)
            }
        }
    }

    public let span: Span
    public let entry: JournalEntry

    public var id: DayID { entry.day }
}

extension AppData {
    /// What was written on the same date a week, a month, a year and two years before `day`:
    /// only days with something to read again (a win, a reflection or an intention).
    public func memories(for day: DayID) -> [JournalMemory] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let date = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else { return [] }
        let byDay = Dictionary(journal.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        return JournalMemory.Span.allCases.compactMap { span in
            guard let past = calendar.date(byAdding: span.components, to: date) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: past)
            guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day,
                  let entry = byDay[DayID(year: year, month: month, day: dayOfMonth)],
                  !entry.win.isEmpty || !entry.reflection.isEmpty || !entry.intention.isEmpty else { return nil }
            return JournalMemory(span: span, entry: entry)
        }
    }
}
