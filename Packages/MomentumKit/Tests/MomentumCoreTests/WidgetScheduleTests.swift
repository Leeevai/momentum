import Foundation
import Testing
@testable import MomentumCore

@Suite("Widget schedule")
struct WidgetScheduleTests {
    @Test("Idle: now and the next midnight")
    func idle() {
        let dates = WidgetSchedule.entryDates(for: AppData(), now: referenceNow, calendar: testCalendar)
        #expect(dates == [referenceNow, date(2026, 10, 9, 0)])
    }

    @Test("Running: every five minutes, the planned end, and midnight")
    func running() {
        let goal = Goal(name: "Focus", kind: .time, target: 3600)
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, planned: 25 * 60, at: referenceNow.addingTimeInterval(-60), calendar: testCalendar)
        let dates = WidgetSchedule.entryDates(for: data, now: referenceNow, calendar: testCalendar)
        #expect(dates.first == referenceNow)
        #expect(dates.contains(referenceNow.addingTimeInterval(55 * 60)))
        #expect(dates.contains(referenceNow.addingTimeInterval(24 * 60)))   // planned end
        #expect(dates.last == date(2026, 10, 9, 0))
        #expect(dates == dates.sorted())
        #expect(dates.count == 14)
    }

    @Test("Paused: no extra frames")
    func paused() {
        let goal = Goal(name: "Focus", kind: .time, target: 3600)
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, at: referenceNow.addingTimeInterval(-600), calendar: testCalendar)
        data.pauseFocus(at: referenceNow)
        #expect(WidgetSchedule.entryDates(for: data, now: referenceNow, calendar: testCalendar).count == 2)
    }
}
