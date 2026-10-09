import Foundation

/// When widget timelines need a fresh render.
///
/// Counters tick on their own (`Text` timer styles), but rings only move when an entry renders.
/// A running session therefore gets an entry every five minutes for the next hour (plus its
/// planned end and midnight when they fall inside it), and the timeline is rebuilt when they run
/// out. Otherwise nothing changes until midnight, when "today" rolls over.
public enum WidgetSchedule {
    public static let runningInterval: TimeInterval = 5 * 60
    public static let runningEntries = 12

    public static func entryDates(for data: AppData, now: Date, calendar: Calendar = .current) -> [Date] {
        var dates = [now]
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        if let session = data.session, session.isRunning {
            let horizon = now.addingTimeInterval(Double(runningEntries - 1) * runningInterval)
            dates += (1..<runningEntries).map { now.addingTimeInterval(Double($0) * runningInterval) }
            // Only moments inside the hour: the timeline must end there to be rebuilt.
            for moment in [session.plannedEnd, midnight].compactMap({ $0 }) where moment > now && moment < horizon {
                dates.append(moment)
            }
        } else if let midnight {
            dates.append(midnight)
        }
        return Array(Set(dates)).sorted()
    }
}
