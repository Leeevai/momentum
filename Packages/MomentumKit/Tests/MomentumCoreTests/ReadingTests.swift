import Foundation
import Testing
@testable import MomentumCore

@Suite("Reading on a pages goal")
struct ReadingTests {
    private func pagesGoal(unit: String = "pages") -> Goal {
        Goal(name: "Read", kind: .amount, unit: unit, period: .daily, target: 10, quickAddStep: 10,
             createdAt: testCalendar.date(byAdding: .day, value: -30, to: referenceNow)!)
    }

    @Test("Only amount goals counted in pages track a book")
    func tracksPages() {
        let flags = ["pages", " Pages ", "page", "pg", "PGS", "km", ""].map { pagesGoal(unit: $0).tracksPages }
        let count = Goal(name: "Gym", kind: .count, unit: "pages", target: 1)
        #expect(flags == [true, true, true, true, true, false, false])
        #expect(!count.tracksPages)
    }

    @Test("Logging pages moves the bookmark of the book being read, and counts in full")
    func bookmarkMoves() {
        var goal = pagesGoal()
        let book = Book(title: "Algorithms", totalPages: 100, currentPage: 40, status: .reading, startedAt: referenceNow)
        goal.books = [book]
        var data = AppData(goals: [goal])
        data.quickAdd(to: goal.id, at: referenceNow)
        data.logReading(15, for: goal.id, at: referenceNow, note: "Chapter 3")
        let page = data.goal(goal.id)?.books.first?.currentPage
        let logged = data.entries.map(\.amount)
        let inBook = data.entries.allSatisfy { $0.bookID == book.id }
        let amount = engine(data).amount(for: goal, on: referenceNow, now: referenceNow)
        #expect(page == 65)
        #expect(logged == [10, 15])
        #expect(inBook)
        #expect(amount == 25)
    }

    @Test("The last page finishes the book, pages past it still count, and then logs are plain")
    func lastPage() throws {
        var goal = pagesGoal()
        goal.books = [Book(title: "Short", totalPages: 50, currentPage: 45, status: .reading, startedAt: referenceNow)]
        var data = AppData(goals: [goal])
        data.logReading(10, for: goal.id, at: referenceNow)
        let finished = try #require(data.goal(goal.id)?.books.first)
        let logged = data.entries.map(\.amount)
        #expect(finished.currentPage == 50)
        #expect(finished.status == .finished)
        #expect(logged == [10])
        // No book being read now.
        data.logReading(5, for: goal.id, at: referenceNow)
        let last = try #require(data.entries.last)
        #expect(last.bookID == nil)
        #expect(last.amount == 5)
    }

    @Test("A correction moves the bookmark back, never before the first page")
    func correction() {
        var goal = pagesGoal()
        goal.books = [Book(title: "Algorithms", totalPages: 100, currentPage: 5, status: .reading, startedAt: referenceNow)]
        var data = AppData(goals: [goal])
        data.logReading(-10, for: goal.id, at: referenceNow)
        let page = data.goal(goal.id)?.books.first?.currentPage
        #expect(page == 0)
    }

    @Test("Goals in other units log as they did")
    func otherUnits() {
        var distance = pagesGoal(unit: "km")
        distance.books = [Book(title: "Odd", totalPages: 100, currentPage: 5, status: .reading, startedAt: referenceNow)]
        var data = AppData(goals: [distance])
        data.quickAdd(to: distance.id, at: referenceNow)
        let page = data.goal(distance.id)?.books.first?.currentPage
        let bookID = data.entries.first?.bookID
        #expect(page == 5)
        #expect(bookID == nil)
    }

    @Test("The watch gets the page reached in the book being read")
    func watchBookmark() {
        var reading = pagesGoal()
        reading.books = [Book(title: "Algorithms", totalPages: 420, currentPage: 134, status: .reading, startedAt: referenceNow)]
        let plain = pagesGoal()
        let snapshot = engine(AppData(goals: [reading, plain])).watchSnapshot(now: referenceNow)
        let marked = snapshot.item(reading.id)?.bookmark
        let unmarked = snapshot.item(plain.id)?.bookmark
        #expect(marked == "Page 134 of 420")
        #expect(unmarked == nil)
    }
}
