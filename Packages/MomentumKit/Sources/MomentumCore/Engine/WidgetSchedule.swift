import Foundation

/// When widget timelines need a fresh render.
///
/// Counters tick on their own (`Text` timer styles), but rings only move when an entry renders.
/// A running session therefore gets an entry every five minutes for an hour, plus one at its
/// planned end; otherwise nothing changes until midnight, when "today" rolls over.
public enum WidgetSchedule {
    public static let runningInterval: TimeInterval = 5 * 60
    public static let runningEntries = 12

    public static func entryDates(for data: AppData, now: Date, calendar: Calendar = .current) -> [Date] {
        var dates = [now]
        if let session = data.session, session.isRunning {
            dates += (1..<runningEntries).map { now.addingTimeInterval(Double($0) * runningInterval) }
            if let end = session.plannedEnd, end > now { dates.append(end) }
        }
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.append(midnight)
        }
        return Array(Set(dates)).sorted()
    }
}
