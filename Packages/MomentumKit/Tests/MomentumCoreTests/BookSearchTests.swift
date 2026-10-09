import Foundation
import Testing
@testable import MomentumCore

@Suite("Book search")
struct BookSearchTests {
    @Test("Search responses become results; entries without a title are skipped")
    func parsesResults() throws {
        let url = try #require(Bundle.module.url(forResource: "openlibrary-search", withExtension: "json", subdirectory: "Fixtures"))
        let results = try OpenLibrary.parse(Data(contentsOf: url))
        #expect(results.count == 2)

        let dune = try #require(results.first)
        #expect(dune.title == "Dune")
        #expect(dune.author == "Frank Herbert")
        #expect(dune.pages == 517)
        #expect(dune.year == 1965)
        #expect(dune.coverURL?.absoluteString == "https://covers.openlibrary.org/b/id/11481354-M.jpg")
        #expect(dune.link.absoluteString == "https://openlibrary.org/works/OL893415W")

        let systems = results[1]
        #expect(systems.author == "Donella H. Meadows, Diana Wright")
        #expect(systems.pages == nil)
        #expect(systems.coverURL == nil)
    }

    @Test("Short queries make no request; others are encoded")
    func searchURL() throws {
        #expect(OpenLibrary.searchURL(for: " a ") == nil)
        let url = try #require(OpenLibrary.searchURL(for: "project hail mary"))
        #expect(url.absoluteString.hasPrefix("https://openlibrary.org/search.json?q=project%20hail%20mary"))
    }

    @Test("A result becomes a pre-filled book")
    func makesBook() {
        let result = BookSearchResult(id: "/works/1", title: "Piranesi", author: "Susanna Clarke", pages: 272, year: 2020,
                                      coverURL: URL(string: "https://covers.openlibrary.org/b/id/1-M.jpg"), link: URL(string: "https://openlibrary.org/works/1")!)
        let book = result.makeBook(status: .reading)
        #expect(book.title == "Piranesi")
        #expect(book.totalPages == 272)
        #expect(book.status == .reading)
        #expect(book.coverURL == result.coverURL)
    }
}
