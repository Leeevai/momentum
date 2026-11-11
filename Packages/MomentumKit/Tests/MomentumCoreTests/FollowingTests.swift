import Foundation
import Testing
@testable import MomentumCore

@Suite("Following a book, course, series or video")
struct FollowingTests {
    private func goal(_ kind: GoalKind, unit: String = "", step: Double = 1) -> Goal {
        Goal(name: "Learn", kind: kind, unit: unit, period: .weekly, target: 10, quickAddStep: step,
             createdAt: testCalendar.date(byAdding: .day, value: -30, to: referenceNow)!)
    }

    private func reading(_ total: Int?, at position: Int) -> Book {
        Book(title: "Item", totalPages: total, currentPage: position, status: .reading, startedAt: referenceNow)
    }

    @Test("What a goal follows comes from its kind and unit")
    func followsFromUnit() {
        let amounts = ["pages", " Lessons ", "module", "classes", "lecture", "Episodes", "eps", "videos", "km", ""]
            .map { goal(.amount, unit: $0).follows }
        let counts = ["pages", "lessons", "episodes", "workouts"].map { goal(.count, unit: $0).follows }
        let others = [goal(.books), goal(.time), goal(.milestones)].map(\.follows)
        #expect(amounts == [.book, .course, .course, .course, .course, .series, .series, .series, nil, nil])
        #expect(counts == [nil, .course, .series, nil])
        #expect(others == [.book, .video, nil])
    }

    @Test("Lessons logged move the course along; setting the lesson logs the difference and finishes it")
    func course() throws {
        var course = goal(.amount, unit: "lessons")
        let item = reading(12, at: 5)
        course.books = [item]
        var data = AppData(goals: [course])
        data.logReading(2, for: course.id, at: referenceNow)
        let afterLog = data.goal(course.id)?.books.first?.currentPage
        data.setPage(10, in: item.id, of: course.id, at: referenceNow, note: "Unit 3")
        let afterSet = data.goal(course.id)?.books.first?.currentPage
        let note = data.entries.last?.note
        data.setPage(12, in: item.id, of: course.id, at: referenceNow)
        let finished = try #require(data.goal(course.id)?.books.first)
        let logged = data.entries.map(\.amount)
        let inCourse = data.entries.allSatisfy { $0.bookID == item.id }
        #expect(afterLog == 7)
        #expect(afterSet == 10)
        #expect(note == "Unit 3")
        #expect(logged == [2, 3, 2])
        #expect(inCourse)
        #expect(finished.status == .finished)
        #expect(finished.currentPage == 12)
    }

    @Test("Quick add on a series goal moves to the next episode")
    func seriesQuickAdd() {
        var series = goal(.count, unit: "episodes")
        let item = reading(10, at: 4)
        series.books = [item]
        var data = AppData(goals: [series])
        data.quickAdd(to: series.id, at: referenceNow)
        let episode = data.goal(series.id)?.books.first?.currentPage
        let entry = data.entries.first
        #expect(episode == 5)
        #expect(entry?.amount == 1)
        #expect(entry?.bookID == item.id)
    }

    @Test("A video on a time goal: watched up to logs the time since, logged time moves it, the timer doesn't")
    func video() {
        var watch = goal(.time, step: 15 * 60)
        let lecture = reading(2 * 3600 + 10 * 60, at: 0)
        watch.books = [lecture]
        var data = AppData(goals: [watch])
        data.setPage(3600 + 23 * 60 + 40, in: lecture.id, of: watch.id, at: referenceNow)
        let upTo = data.goal(watch.id)?.books.first?.currentPage
        data.logReading(600, for: watch.id, at: referenceNow)
        let afterLog = data.goal(watch.id)?.books.first?.currentPage
        data.startFocus(on: watch.id, at: referenceNow, calendar: testCalendar)
        data.stopFocus(at: referenceNow.addingTimeInterval(1800), calendar: testCalendar)
        let afterTimer = data.goal(watch.id)?.books.first?.currentPage
        let timed = data.entries.last
        let amount = engine(data).amount(for: watch, on: referenceNow, now: referenceNow.addingTimeInterval(1800))
        #expect(upTo == 5020)
        #expect(afterLog == 5620)
        #expect(afterTimer == 5620)
        #expect(timed?.bookID == nil)
        #expect(timed?.source == .timer)
        let expected: Double = 5020 + 600 + 1800
        #expect(amount == expected)
    }

    @Test("A goal following nothing, or nothing in progress, logs plain amounts")
    func plain() {
        let work = goal(.time, step: 15 * 60)
        var course = goal(.amount, unit: "lessons")
        course.books = [Book(title: "Next", totalPages: 10, status: .wantToRead)]
        var data = AppData(goals: [work, course])
        data.quickAdd(to: work.id, at: referenceNow)
        data.quickAdd(to: course.id, at: referenceNow)
        let books = data.entries.map(\.bookID)
        let amounts = data.entries.map(\.amount)
        let untouched = data.goal(course.id)?.books.first?.currentPage
        #expect(books == [nil, nil])
        #expect(amounts == [900, 1])
        #expect(untouched == 0)
    }

    @Test("Where an item is up to, and what's left, in the goal's own words")
    func wording() {
        let book = goal(.amount, unit: "pages")
        let course = goal(.amount, unit: "classes")
        let series = goal(.amount, unit: "episodes")
        let video = goal(.time)
        let texts = [
            book.positionText(of: reading(420, at: 134)), book.remainingText(of: reading(420, at: 134)) ?? "",
            course.positionText(of: reading(24, at: 23)), course.remainingText(of: reading(24, at: 23)) ?? "",
            series.positionText(of: reading(nil, at: 5)),
            video.positionText(of: reading(7800, at: 5020)), video.remainingText(of: reading(7800, at: 5020)) ?? "",
        ]
        let noLength = series.remainingText(of: reading(nil, at: 5))
        let parts = [course.formatParts(1), course.formatParts(3), video.formatParts(2400)]
        #expect(texts == ["Page 134 of 420", "286 pages left", "Class 23 of 24", "1 class left", "Episode 5",
                          "1:23:40 of 2:10:00", "46:20 left"])
        #expect(noLength == nil)
        #expect(parts == ["1 class", "3 classes", "40m"])
    }

    @Test("The watch's bookmark line reads in the goal's own words")
    func watchBookmark() throws {
        var course = goal(.amount, unit: "lessons")
        course.books = [reading(24, at: 7)]
        var video = goal(.time)
        video.books = [reading(7800, at: 5020)]
        let gym = checkInGoal()
        let snapshot = engine(AppData(goals: [course, video, gym])).watchSnapshot(now: referenceNow)
        let marks = [course, video, gym].map { snapshot.item($0.id)?.bookmark }
        #expect(marks == ["Lesson 7 of 24", "1:23:40 of 2:10:00", nil])
    }

    @Test("A finished course isn't a finished book")
    func achievementsCountBooksOnly() throws {
        var course = goal(.amount, unit: "lessons")
        course.books = [Book(title: "Swift", totalPages: 10, currentPage: 10, status: .finished, finishedAt: referenceNow)]
        var books = goal(.books)
        books.books = [Book(title: "Dune", totalPages: 400, currentPage: 400, status: .finished, finishedAt: referenceNow)]
        let progress = engine(AppData(goals: [course, books])).achievements(now: referenceNow)
        let finished = try #require(progress.first { $0.id == "book-10" }).value
        #expect(finished == 1)
    }

    @Test("The course and series templates follow what they say")
    func templates() {
        let follows = ["course-lessons", "lecture-series"].map { id in GoalTemplate.all.first { $0.id == id }?.prototype.follows }
        #expect(follows == [.course, .series])
    }
}

@Suite("Typed times and paces")
struct ClockAndPaceTests {
    @Test("A typed stopwatch reading becomes seconds; a bare number is minutes")
    func clock() {
        let parsed = ["1:23:40", "23:40", "45", " 2:05:00 ", "0:00", "90:00"].map(Formatting.seconds(fromClock:))
        let refused = ["", "1:60", "1:2:3:4", "-5", "1.5", "a:10", "1::2", "١٢"].map(Formatting.seconds(fromClock:))
        #expect(parsed == [5020, 1420, 2700, 7500, 0, 5400])
        #expect(refused.allSatisfy { $0 == nil })
    }

    @Test("Pace shows on distance goals only")
    func pace() {
        let run = Goal(name: "Run", kind: .amount, unit: "km", target: 5)
        let walk = Goal(name: "Walk", kind: .amount, unit: " Miles", target: 2)
        let gym = checkInGoal()
        let paces = [run.paceText(amount: 5, duration: 28 * 60), walk.paceText(amount: 2, duration: 30 * 60),
                     run.paceText(amount: 0, duration: 600), gym.paceText(amount: 1, duration: 600)]
        #expect(paces == ["5:36/km", "15:00/mi", nil, nil])
    }

    @Test("What a goal follows, in the plural")
    func plurals() {
        let plurals = FollowKind.allCases.map(\.pluralNoun)
        #expect(plurals == ["books", "courses", "series", "videos"])
    }
}
