import Foundation
import Testing
@testable import MomentumCore

@Suite("Journal")
struct JournalTests {
    @Test("A day id survives a round trip through JSON and sorts by date")
    func dayIDCoding() throws {
        let day = DayID(referenceNow, calendar: testCalendar)
        #expect(day.description == "2026-10-08")
        let data = try JSONEncoder().encode([day])
        #expect(String(decoding: data, as: UTF8.self) == "[\"2026-10-08\"]")
        #expect(try JSONDecoder().decode([DayID].self, from: data) == [day])
        #expect(DayID(year: 2026, month: 9, day: 30) < day)
        #expect(DayID(string: "2026-13-01") == nil)
    }

    @Test("Editing a day creates its entry, and emptying it removes it")
    func createAndRemove() {
        var data = AppData()
        let day = DayID(referenceNow, calendar: testCalendar)
        data.updateJournal(for: day, at: referenceNow) { $0.intention = "Ship the release" }
        #expect(data.journalEntry(for: day)?.intention == "Ship the release")
        #expect(data.journalEntry(for: day)?.modifiedAt == referenceNow)
        data.updateJournal(for: day, at: referenceNow) { $0.intention = "" }
        #expect(data.journal.isEmpty)
    }

    @Test("Priorities toggle and stop at three")
    func priorities() {
        let goals = (0..<4).map { Goal(name: "G\($0)", kind: .count, target: 1) }
        var data = AppData(goals: goals)
        let day = DayID(referenceNow, calendar: testCalendar)
        for goal in goals { data.togglePriority(goal.id, on: day) }
        #expect(data.journalEntry(for: day)?.priorities == goals.prefix(3).map(\.id))
        data.togglePriority(goals[1].id, on: day)
        #expect(data.journalEntry(for: day)?.priorities == [goals[0].id, goals[2].id])
    }

    @Test("Undo puts a journal day back as it was")
    func undoJournal() {
        var data = AppData()
        let day = DayID(referenceNow, calendar: testCalendar)
        data.updateJournal(for: day) { $0.mood = .good }
        let before = data
        data.updateJournal(for: day) { $0.mood = .great; $0.win = "Finished the draft" }
        DataPatch(from: before, to: data).undo(on: &data)
        #expect(data.journalEntry(for: day)?.mood == .good)
        #expect(data.journalEntry(for: day)?.win == "")
    }

    @Test("A damaged journal entry is skipped instead of failing the file")
    func lossyJournal() throws {
        let json = #"{"goals":[],"entries":[],"journal":[{"day":"2026-10-08","mood":4},{"day":"not a day"},{"day":"2026-10-07","mood":9}]}"#
        let data = try JSONDecoder().decode(AppData.self, from: Data(json.utf8))
        #expect(data.journal.map(\.day.description) == ["2026-10-08", "2026-10-07"])
        #expect(data.journal.first?.mood == .good)
        #expect(data.journal.last?.mood == nil)
    }
}
