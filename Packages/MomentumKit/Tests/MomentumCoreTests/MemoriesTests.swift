import Foundation
import Testing
@testable import MomentumCore

@Suite("Journal memories")
struct MemoriesTests {
    private func entry(_ day: DayID, win: String = "", mood: Mood? = nil) -> JournalEntry {
        var entry = JournalEntry(day: day)
        entry.win = win
        entry.mood = mood
        return entry
    }

    @Test("Days a week, a month and a year back come up, newest first, if there's something to read")
    func memories() {
        var data = AppData()
        data.journal = [
            entry(DayID(year: 2026, month: 10, day: 1), win: "Shipped the widget"),
            entry(DayID(year: 2026, month: 9, day: 8), win: "First 5k"),
            entry(DayID(year: 2025, month: 10, day: 8), win: "Started Spanish"),
            // A mood alone isn't something to read again.
            entry(DayID(year: 2024, month: 10, day: 8), mood: .good),
        ]
        let memories = data.memories(for: DayID(year: 2026, month: 10, day: 8))
        #expect(memories.map(\.span) == [.week, .month, .year])
        #expect(memories.map(\.entry.win) == ["Shipped the widget", "First 5k", "Started Spanish"])
    }

    @Test("A month back from the 31st lands on the last day of a shorter month")
    func shortMonth() {
        var data = AppData()
        data.journal = [entry(DayID(year: 2026, month: 2, day: 28), win: "Leap")]
        #expect(data.memories(for: DayID(year: 2026, month: 3, day: 31)).map(\.span) == [.month])
    }
}
