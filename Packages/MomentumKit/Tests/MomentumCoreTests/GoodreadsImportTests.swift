import Foundation
import Testing
@testable import MomentumCore

@Suite("Goodreads import")
struct GoodreadsImportTests {
    func fixture() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "goodreads_library_export", withExtension: "csv", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Shelves, dates, ratings and pages carry over")
    func importsLibrary() throws {
        let books = try GoodreadsImporter.books(fromCSV: fixture(), now: referenceNow, calendar: testCalendar)
        #expect(books.map(\.title) == ["Dune", "Project Hail Mary", "Atomic Habits"])

        let dune = books[0]
        #expect(dune.status == .finished)
        #expect(dune.author == "Frank Herbert")
        #expect(dune.rating == 5)
        #expect(dune.totalPages == 617)
        #expect(dune.currentPage == 617)
        #expect(dune.finishedAt == date(2024, 5, 14))
        #expect(dune.link?.absoluteString == "https://www.goodreads.com/book/show/234225")

        #expect(books[1].status == .reading)
        #expect(books[1].rating == nil)
        #expect(books[1].startedAt == date(2025, 1, 10))

        #expect(books[2].status == .wantToRead)
        #expect(books[2].totalPages == nil)
    }

    @Test("Books already on the list are skipped")
    func skipsExisting() throws {
        let existing = [Book(title: "dune", author: "Frank Herbert")]
        let books = try GoodreadsImporter.books(fromCSV: fixture(), existing: existing, now: referenceNow, calendar: testCalendar)
        #expect(books.map(\.title) == ["Project Hail Mary", "Atomic Habits"])
    }

    @Test("Other files are rejected")
    func rejectsOtherCSV() {
        #expect(throws: GoodreadsImporter.ImportError.notGoodreadsExport) {
            try GoodreadsImporter.books(fromCSV: "name,amount\nRun,5\n")
        }
    }

    @Test("Quoted fields keep commas, quotes and line breaks")
    func csvParser() {
        let rows = CSVParser.rows("a,\"b, c\",\"say \"\"hi\"\"\"\r\n\"two\nlines\",x\n\n")
        #expect(rows == [["a", "b, c", "say \"hi\""], ["two\nlines", "x"]])
    }
}
