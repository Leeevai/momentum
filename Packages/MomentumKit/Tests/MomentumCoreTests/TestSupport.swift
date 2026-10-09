import Foundation
@testable import MomentumCore

/// A fixed Gregorian calendar (Chicago, so DST transitions are real; weeks start Monday),
/// so results never depend on the machine running the tests.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    calendar.firstWeekday = 2
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}()

/// Local wall-clock time in the test calendar.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Thursday 8 October 2026, 3 pm.
let referenceNow = date(2026, 10, 8, 15)

func engine(_ data: AppData) -> ProgressEngine {
    ProgressEngine(data: data, calendar: testCalendar)
}

func checkInGoal(weekdays: Set<Int> = Set(1...7), createdDaysAgo: Int = 30, period: GoalPeriod = .daily, target: Double = 1) -> Goal {
    Goal(name: "Gym", kind: .count, unit: "workouts", period: period, target: target, weekdays: weekdays,
         createdAt: testCalendar.date(byAdding: .day, value: -createdDaysAgo, to: referenceNow)!)
}

func dayOffset(_ offset: Int, hour: Int = 12) -> Date {
    let start = testCalendar.date(byAdding: .day, value: offset, to: testCalendar.startOfDay(for: referenceNow))!
    return testCalendar.date(bySettingHour: hour, minute: 0, second: 0, of: start)!
}

func timeGoal(minutes: Int? = 25, target: Double = 3600, createdDaysAgo: Int = 30) -> Goal {
    Goal(name: "Deep work", kind: .time, target: target, focusMinutes: minutes,
         createdAt: testCalendar.date(byAdding: .day, value: -createdDaysAgo, to: referenceNow)!)
}
