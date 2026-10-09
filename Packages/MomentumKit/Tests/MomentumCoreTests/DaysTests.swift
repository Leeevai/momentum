import Foundation
import Testing
@testable import MomentumCore

@Suite("Days and stacks")
struct DaysTests {
    @Test("Stacked goals follow their anchor; loops keep their places")
    func stackOrder() {
        let a = checkInGoal()
        var b = checkInGoal()
        var c = checkInGoal()
        let d = checkInGoal()
        b.stackAfter = d.id
        c.stackAfter = a.id
        let data = AppData(goals: [a, b, c, d])
        #expect(engine(data).stackOrdered(data.goals).map(\.id) == [a.id, c.id, d.id, b.id])

        var x = checkInGoal()
        var y = checkInGoal()
        x.stackAfter = y.id
        y.stackAfter = x.id
        let looped = AppData(goals: [x, y])
        #expect(engine(looped).stackOrdered(looped.goals).map(\.id) == [x.id, y.id])
    }

    @Test("A goal can't be stacked after one already stacked after it")
    func anchorsAvoidLoops() {
        let a = checkInGoal()
        var b = checkInGoal()
        b.stackAfter = a.id
        let data = AppData(goals: [a, b])
        #expect(engine(data).possibleAnchors(for: a).isEmpty)
        #expect(engine(data).possibleAnchors(for: b).map(\.id) == [a.id])
    }

    @Test("A day summary counts what was due and met, and the day's focus")
    func summary() {
        let gym = checkInGoal()
        let work = timeGoal(target: 1800)
        var data = AppData(goals: [gym, work])
        data.entries.append(LogEntry(goalID: work.id, date: dayOffset(-1, hour: 9), amount: 2000, source: .timer))
        let summary = engine(data).daySummary(dayOffset(-1), now: referenceNow)
        #expect(Set(summary.due) == [gym.id, work.id])
        #expect(summary.met == [work.id])
        #expect(summary.focusSeconds == 2000.0)
        #expect(summary.completion == 0.5)
    }

    @Test("The timeline shows logged sessions and the running one")
    func timeline() {
        let work = timeGoal()
        var data = AppData(goals: [work])
        data.entries.append(LogEntry(goalID: work.id, date: dayOffset(0, hour: 9), amount: 3600, source: .timer))
        data.entries.append(LogEntry(goalID: work.id, date: dayOffset(0, hour: 10), amount: 600, source: .manual))
        data.startFocus(on: work.id, at: referenceNow.addingTimeInterval(-600), calendar: testCalendar)
        let blocks = engine(data).timeline(on: referenceNow, now: referenceNow)
        #expect(blocks.count == 2)
        #expect(blocks[0].interval.duration == 3600.0)
        #expect(blocks[1].isLive)
        #expect(blocks[1].interval.duration == 600.0)
    }

    @Test("A month grid pads to whole weeks starting on the calendar's first weekday")
    func monthGrid() {
        let grid = engine(AppData()).monthGrid(containing: referenceNow)
        #expect(grid.allSatisfy { $0.count == 7 })
        // October 2026 starts on a Thursday; weeks start Monday.
        #expect(grid[0].prefix(3).allSatisfy { $0 == nil })
        #expect(grid[0][3] == testCalendar.startOfDay(for: date(2026, 10, 1)))
        #expect(grid.flatMap { $0 }.compactMap { $0 }.count == 31)
    }

    @Test("Mood lines up with good days")
    func moods() {
        let gym = checkInGoal()
        var data = AppData(goals: [gym])
        data.log(1, for: gym.id, at: dayOffset(-2))
        data.updateJournal(for: DayID(dayOffset(-2), calendar: testCalendar)) { $0.mood = .great }
        data.updateJournal(for: DayID(dayOffset(-1), calendar: testCalendar)) { $0.mood = .low; $0.energy = .low }
        let report = engine(data).moodReport(in: DateInterval(start: dayOffset(-7), end: referenceNow), now: referenceNow)
        #expect(report.moodOnGoodDays == 5.0)
        #expect(report.moodOnOtherDays == 2.0)
        #expect(report.days == 2)
        #expect(report.averageEnergy == 2.0)
    }
}
