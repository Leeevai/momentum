import Foundation
import Testing
@testable import MomentumCore

@Suite("Books")
struct BookTests {
    func readingGoal(books: [Book] = []) -> Goal {
        Goal(name: "Read", kind: .books, period: .yearly, target: 12, quickAddStep: 10, books: books, createdAt: date(2026, 1, 1))
    }

    @Test("Logging pages moves the bookmark and starts an unread book")
    func logPagesStartsBook() throws {
        let book = Book(title: "Dune", totalPages: 400)
        let goal = readingGoal(books: [book])
        var data = AppData(goals: [goal])
        data.logPages(30, in: book.id, of: goal.id, at: referenceNow)
        let stored = try #require(data.goal(goal.id)?.books.first)
        #expect(stored.currentPage == 30)
        #expect(stored.status == .reading)
        #expect(stored.startedAt == referenceNow)
        #expect(data.entries.first?.bookID == book.id)
        #expect(data.entries.first?.amount == 30)
    }

    @Test("Reaching the last page finishes the book, without over-logging")
    func reachingEndFinishes() throws {
        let book = Book(title: "Piranesi", totalPages: 272, currentPage: 260, status: .reading)
        let goal = readingGoal(books: [book])
        var data = AppData(goals: [goal])
        data.logPages(50, in: book.id, of: goal.id, at: referenceNow)
        let stored = try #require(data.goal(goal.id)?.books.first)
        #expect(stored.status == .finished)
        #expect(stored.currentPage == 272)
        #expect(stored.finishedAt == referenceNow)
        #expect(data.entries.map(\.amount) == [12])
    }

    @Test("Progress counts books finished this year; activity counts reading days")
    func progressAndStreak() {
        let finishedLastYear = Book(title: "Old", status: .finished, finishedAt: date(2025, 12, 30))
        let finished = Book(title: "New", status: .finished, finishedAt: date(2026, 3, 1))
        let goal = readingGoal(books: [finishedLastYear, finished])
        var data = AppData(goals: [goal])
        for offset in -2...0 { data.log(10, for: goal.id, at: dayOffset(offset)) }
        let e = engine(data)
        #expect(e.currentAmount(for: goal, now: referenceNow) == 1)
        #expect(e.progress(for: goal, now: referenceNow) == 1.0 / 12)
        #expect(e.streak(for: goal, now: referenceNow).current == 3)
    }

    @Test("Quick add logs the step in the book being read")
    func quickAddReadsCurrentBook() throws {
        let queued = Book(title: "Next", totalPages: 300)
        let current = Book(title: "Now", totalPages: 300, currentPage: 100, status: .reading, startedAt: date(2026, 10, 1))
        let goal = readingGoal(books: [queued, current])
        var data = AppData(goals: [goal])
        data.quickAdd(to: goal.id, at: referenceNow)
        let books = try #require(data.goal(goal.id)?.books)
        #expect(books.first { $0.id == current.id }?.currentPage == 110)
        #expect(books.first { $0.id == queued.id }?.currentPage == 0)
    }

    @Test("Finishing logs the remaining pages and records the rating")
    func finishLogsRest() throws {
        let book = Book(title: "Atomic Habits", totalPages: 320, currentPage: 300, status: .reading)
        let goal = readingGoal(books: [book])
        var data = AppData(goals: [goal])
        data.finishBook(book.id, in: goal.id, rating: 5, at: referenceNow)
        let stored = try #require(data.goal(goal.id)?.books.first)
        #expect(stored.rating == 5)
        #expect(stored.status == .finished)
        #expect(data.entries.map(\.amount) == [20])
    }

    @Test("Removing a book removes its page logs")
    func removeBookRemovesLogs() {
        let book = Book(title: "Gone", totalPages: 100)
        let goal = readingGoal(books: [book])
        var data = AppData(goals: [goal])
        data.logPages(10, in: book.id, of: goal.id, at: referenceNow)
        data.removeBook(book.id, from: goal.id)
        #expect(data.entries.isEmpty)
        #expect(data.goal(goal.id)?.books.isEmpty == true)
    }
}

@Suite("Milestones")
struct MilestoneTests {
    @Test("Progress is the share of milestones done, and quick add completes the next one")
    func progress() {
        let goal = Goal(name: "Ship", kind: .milestones, target: 0, milestones: ["A", "B", "C", "D"].map { Milestone(title: $0) }, createdAt: date(2026, 9, 1))
        var data = AppData(goals: [goal])
        data.quickAdd(to: goal.id, at: referenceNow)
        data.quickAdd(to: goal.id, at: referenceNow)
        let stored = data.goal(goal.id)!
        #expect(engine(data).progress(for: stored, now: referenceNow) == 0.5)
        #expect(stored.milestones.map(\.isDone) == [true, true, false, false])

        data.toggleMilestone(stored.milestones[0].id, in: goal.id, at: referenceNow)
        #expect(data.goal(goal.id)!.milestones[0].isDone == false)
    }

    @Test("Moving milestones follows List.onMove semantics")
    func move() {
        var items = ["a", "b", "c", "d"]
        items.move(fromOffsets: IndexSet([0]), toOffset: 3)
        #expect(items == ["b", "c", "a", "d"])
        items.move(fromOffsets: IndexSet([3]), toOffset: 0)
        #expect(items == ["d", "b", "c", "a"])
        items.move(fromOffsets: IndexSet([0, 2]), toOffset: 4)
        #expect(items == ["b", "a", "d", "c"])
    }
}
