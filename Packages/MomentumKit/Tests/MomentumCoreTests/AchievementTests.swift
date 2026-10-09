import Foundation
import Testing
@testable import MomentumCore

@Suite("Achievements")
struct AchievementTests {
    @Test("Achievement ids are unique and targets positive")
    func catalog() {
        #expect(Set(Achievement.all.map(\.id)).count == Achievement.all.count)
        #expect(Achievement.all.allSatisfy { $0.target > 0 })
    }

    @Test("The first log earns First Step, once")
    func firstStep() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        #expect(data.recordAchievements(now: referenceNow, calendar: testCalendar).isEmpty)
        data.log(1, for: goal.id, at: referenceNow)
        let earned = data.recordAchievements(now: referenceNow, calendar: testCalendar).map(\.id)
        #expect(earned.contains("first-step"))
        #expect(data.achievements["first-step"] == referenceNow)
        #expect(data.recordAchievements(now: referenceNow.addingTimeInterval(60), calendar: testCalendar).isEmpty)
    }

    @Test("Streaks, focus hours, sessions and perfect days are measured from history")
    func measured() throws {
        let goal = timeGoal(target: 1800)
        var data = AppData(goals: [goal])
        for offset in -9...0 {
            data.entries.append(LogEntry(goalID: goal.id, date: dayOffset(offset, hour: 6), amount: 95 * 60, source: .timer))
        }
        let progress = engine(data).achievements(now: referenceNow)
        func value(_ id: String) throws -> Double { try #require(progress.first { $0.id == id }).value }
        #expect(try value("streak-7") == 10.0)
        #expect(try value("focus-10") == 950.0 / 60)
        #expect(try value("session-90") == 95.0)
        #expect(try value("early-bird") == 1.0)
        #expect(try value("night-owl") == 0.0)
        #expect(try value("perfect-day") == 10.0)
        #expect(try value("perfect-week") == 10.0)
        #expect(try value("active-7") == 10.0)
        let earned = engine(data).newlyEarnedAchievements(now: referenceNow).map(\.id)
        #expect(earned.contains("streak-7"))
        #expect(earned.contains("session-90"))
        #expect(!earned.contains("streak-30"))
    }

    @Test("Coming back after a week away is a comeback")
    func comeback() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        data.log(1, for: goal.id, at: dayOffset(-12))
        data.log(1, for: goal.id, at: dayOffset(-4))
        let value = engine(data).achievements(now: referenceNow).first { $0.id == "comeback" }?.value
        #expect(value == 1.0)
    }

    @Test("Earned achievements stay earned when an undo removes what earned them")
    func survivesUndo() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        let before = data
        data.log(1, for: goal.id, at: referenceNow)
        data.recordAchievements(now: referenceNow, calendar: testCalendar)
        DataPatch(from: before, to: data).undo(on: &data)
        #expect(data.entries.isEmpty)
        #expect(data.achievements["first-step"] != nil)
    }
}
