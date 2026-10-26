import Foundation
import Testing
@testable import MomentumCore

@Suite("Journal search")
struct JournalSearchTests {
    let monday = DayID(year: 2026, month: 10, day: 5)
    let tuesday = DayID(year: 2026, month: 10, day: 6)
    let wednesday = DayID(year: 2026, month: 10, day: 7)

    func journal() -> [JournalEntry] {
        [
            JournalEntry(day: monday, intention: "Finish the quarterly report", win: "Called Mom"),
            JournalEntry(day: tuesday, reflection: "A long walk by the lake. The report can wait."),
            JournalEntry(day: wednesday, win: "Coffee at Café Lumière with Ana"),
        ]
    }

    @Test("Every word has to match, in any of the day's fields")
    func everyWord() {
        let together = JournalSearch("report mom").matches(in: journal()).map(\.entry.day)
        let apart = JournalSearch("report ana").matches(in: journal()).map(\.entry.day)
        #expect(together == [monday])
        #expect(apart.isEmpty)
    }

    @Test("Case and accents don't matter")
    func caseAndAccents() {
        let found = JournalSearch("cafe LUMIERE").matches(in: journal()).map(\.entry.day)
        #expect(found == [wednesday])
    }

    @Test("Results come newest first")
    func newestFirst() {
        let days = JournalSearch("report").matches(in: journal()).map(\.entry.day)
        #expect(days == [tuesday, monday])
    }

    @Test("A blank query finds nothing")
    func blank() {
        let blank = JournalSearch("   ")
        let found = blank.matches(in: journal())
        #expect(blank.isEmpty)
        #expect(found.isEmpty)
    }

    @Test("The excerpt comes from the first field that matches, around the match, on one line")
    func excerpt() throws {
        let fields = JournalSearch("report").matches(in: journal()).map(\.field)
        let expected: [JournalMatch.Field] = [.reflection, .intention]
        #expect(fields == expected)

        let long = String(repeating: "Slow morning, ", count: 12) + "then the\nbig launch went out at noon. "
            + String(repeating: "Quiet evening. ", count: 10)
        let entry = JournalEntry(day: monday, reflection: long)
        let match = try #require(JournalSearch("launch").matches(in: [entry]).first)
        let excerpt = match.excerpt
        #expect(excerpt.hasPrefix("…"))
        #expect(excerpt.hasSuffix("…"))
        #expect(excerpt.contains("the big launch went out at noon."))
        #expect(!excerpt.contains("\n"))
        #expect(excerpt.count < long.count)
    }

    @Test("A short field is its own excerpt, uncut")
    func shortExcerpt() throws {
        let match = try #require(JournalSearch("mom").matches(in: journal()).first)
        #expect(match.field == .win)
        #expect(match.excerpt == "Called Mom")
    }

    @Test("Ranges mark every word of the query in a text")
    func ranges() {
        let text = "Coffee at Café Lumière with Ana and ana"
        let marked = JournalSearch("cafe ana").ranges(in: text).map { String(text[$0]) }
        #expect(marked == ["Café", "Ana", "ana"])
    }
}
