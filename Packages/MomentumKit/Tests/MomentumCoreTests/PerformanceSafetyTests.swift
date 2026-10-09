import Foundation
import Testing
@testable import MomentumCore

/// The shortcuts taken for speed must give the same answers as the slow way.
@Suite("Fast paths")
struct PerformanceSafetyTests {
    @Test("Day math matches the calendar, across years, leap days and daylight saving")
    func dayMath() {
        var day = date(2023, 12, 25, 0, 30)
        let end = date(2025, 3, 15)
        while day < end {
            let parts = testCalendar.dateComponents([.year, .month, .day, .weekday, .hour], from: day)
            let number = DayMath.localDay(day, testCalendar.timeZone)
            let civil = DayMath.civil(number)
            #expect(civil.year == parts.year && civil.month == parts.month && civil.day == parts.day)
            #expect(DayMath.weekday(number) == parts.weekday)
            #expect(DayMath.days(year: civil.year, month: civil.month, day: civil.day) == number)
            #expect(DayMath.localHour(day, testCalendar.timeZone) == parts.hour)
            day = day.addingTimeInterval(7 * 3600 + 13 * 60)
        }
    }

    @Test("Day ids are Gregorian whatever the device's calendar")
    func gregorianDayIDs() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = testCalendar.timeZone
        #expect(DayID(referenceNow, calendar: japanese) == DayID(year: 2026, month: 10, day: 8))
        #expect(DayID(year: 2026, month: 10, day: 8).date(in: japanese) == testCalendar.startOfDay(for: referenceNow))
    }

    @Test("Editing a past entry changes the streak, even though histories are shared between engines")
    func streakMemoNeverStale() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        for offset in -6...(-1) { data.log(1, for: goal.id, at: dayOffset(offset)) }
        #expect(engine(data).streak(for: goal, now: referenceNow).current == 6)
        let middle = data.entries[3]
        data.deleteEntry(middle.id)
        #expect(engine(data).streak(for: goal, now: referenceNow).current == 2)
        data.entries.append(middle)
        #expect(engine(data).streak(for: goal, now: referenceNow).current == 6)
        data.updateGoal(goal.id) { $0.target = 2 }
        #expect(engine(data).streak(for: data.goal(goal.id)!, now: referenceNow).current == 0)
    }

    @Test("Only the stretch between the common start and end is compared")
    func stretch() {
        let (a, b) = changedStretch([1, 2, 3, 4, 5], [1, 2, 9, 4, 5])
        #expect(Array(a) == [3] && Array(b) == [9])
        let (c, d) = changedStretch([1, 2, 3], [1, 2, 3, 4])
        #expect(c.isEmpty && Array(d) == [4])
        let (e, f) = changedStretch([1, 2, 2], [2, 2])
        #expect(Array(e) == [1] && f.isEmpty)
    }

    @Test("A moved entry still shows up in the patch")
    func movedEntry() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        for offset in -5...(-1) { data.log(1, for: goal.id, at: dayOffset(offset)) }
        let before = data
        var moved = data.entries[1]
        moved.date = dayOffset(0)
        data.entries.remove(at: 1)
        data.entries.append(moved)
        var undone = data
        DataPatch(from: before, to: data).undo(on: &undone)
        #expect(undone.entries.first { $0.id == moved.id }?.date == before.entries[1].date)
    }

    @Test("Entries leave out default values, and read back the same")
    func leanEntries() throws {
        let plain = LogEntry(goalID: UUID(), date: referenceNow, amount: 2)
        let full = LogEntry(goalID: UUID(), date: referenceNow, amount: 1500, source: .timer, note: "Draft", bookID: UUID())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let text = String(decoding: try encoder.encode(plain), as: UTF8.self)
        #expect(!text.contains("note") && !text.contains("source") && !text.contains("bookID"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for entry in [plain, full] {
            #expect(try decoder.decode(LogEntry.self, from: encoder.encode(entry)) == entry)
        }
    }

    @Test("The file store rereads a file another process changed")
    func readCache() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("data.json")
        let app = FileStore(fileURL: url)
        let widget = FileStore(fileURL: url)
        let goal = checkInGoal()
        app.update { $0.upsert(goal) }
        #expect(app.load().goals.count == 1)
        widget.update { $0.log(1, for: goal.id, at: referenceNow) }
        #expect(app.load().entries.count == 1)
        app.update { $0.log(1, for: goal.id, at: referenceNow) }
        #expect(widget.load().entries.count == 2)
    }
}
