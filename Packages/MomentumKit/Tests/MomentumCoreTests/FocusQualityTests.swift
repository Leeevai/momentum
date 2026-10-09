import Foundation
import Testing
@testable import MomentumCore

@Suite("Focus quality")
struct FocusQualityTests {
    private func session(_ goal: Goal, day: Int, hour: Int, minutes: Double, quality: FocusQuality?) -> LogEntry {
        LogEntry(goalID: goal.id, date: dayOffset(day, hour: hour), amount: minutes * 60, source: .timer, quality: quality)
    }

    private var lastWeek: DateInterval {
        DateInterval(start: dayOffset(-7, hour: 0), end: dayOffset(1, hour: 0))
    }

    @Test("Rated time adds up by quality, and unrated sessions are left out")
    func totals() {
        let goal = timeGoal()
        var data = AppData(goals: [goal])
        data.entries = [
            session(goal, day: -1, hour: 9, minutes: 50, quality: .flow),
            session(goal, day: -1, hour: 14, minutes: 25, quality: .scattered),
            session(goal, day: -2, hour: 9, minutes: 30, quality: nil),
        ]
        let report = engine(data).focusQualityReport(in: lastWeek)
        #expect(report.seconds[.flow] == 3000)
        #expect(report.seconds[.scattered] == 1500)
        #expect(report.ratedSessions == 2)
        #expect(report.flowShare == 3000.0 / 4500.0)
        #expect(report.bestHour == nil)
    }

    @Test("The best hour is the one whose sessions go best, once there are enough")
    func bestHour() {
        let goal = timeGoal()
        var data = AppData(goals: [goal])
        for day in -6 ... -1 {
            data.entries.append(session(goal, day: day, hour: 9, minutes: 45, quality: .flow))
            data.entries.append(session(goal, day: day, hour: 15, minutes: 45, quality: .steady))
        }
        // One perfect session at 7 isn't enough to count.
        data.entries.append(session(goal, day: -3, hour: 7, minutes: 90, quality: .flow))
        #expect(engine(data).focusQualityReport(in: lastWeek).bestHour == 9)
    }

    @Test("Rating a session sets every entry it logged")
    func rate() {
        let goal = timeGoal()
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, at: dayOffset(-1, hour: 23), calendar: testCalendar)
        let logged = data.stopFocus(at: dayOffset(0, hour: 1), calendar: testCalendar)
        #expect(logged.count == 2)
        data.rateSession(Set(logged.map(\.id)), quality: .steady)
        #expect(data.entries.allSatisfy { $0.quality == .steady })
    }

    @Test("A rating survives saving; an unknown one is dropped, not the entry")
    func coding() throws {
        let entry = LogEntry(goalID: UUID(), date: referenceNow, amount: 600, source: .timer, quality: .flow)
        let decoded = try DateCoding.decoder().decode(LogEntry.self, from: DateCoding.encoder().encode(entry))
        #expect(decoded.quality == .flow)

        var json = try #require(String(data: DateCoding.encoder().encode(entry), encoding: .utf8))
        json = json.replacingOccurrences(of: "\"quality\":3", with: "\"quality\":9")
        let future = try DateCoding.decoder().decode(LogEntry.self, from: Data(json.utf8))
        #expect(future.quality == nil)
        #expect(future.amount == 600)
    }
}

@Suite("Focus quality coaching")
struct FocusQualityCoachTests {
    @Test("Once sessions are rated, the coach suggests the hour they go best")
    func flowHourTip() {
        let goal = timeGoal(target: 7200)
        var data = AppData(goals: [goal])
        for day in -10 ... -1 {
            data.entries.append(LogEntry(goalID: goal.id, date: dayOffset(day, hour: 9), amount: 2700, source: .timer, quality: .flow))
            data.entries.append(LogEntry(goalID: goal.id, date: dayOffset(day, hour: 16), amount: 2700, source: .timer, quality: .scattered))
        }
        let tips = engine(data).coachTips(now: dayOffset(0, hour: 8), limit: 10)
        #expect(tips.contains { $0.id == "flow-\(goal.id)" })
        #expect(!engine(data).coachTips(now: dayOffset(0, hour: 13), limit: 10).contains { $0.id == "flow-\(goal.id)" })
    }
}
