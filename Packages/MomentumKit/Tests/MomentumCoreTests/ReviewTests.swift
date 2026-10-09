import Foundation
import Testing
@testable import MomentumCore

@Suite("Week in review")
struct ReviewTests {
    @Test("A week's review totals focus against the week before, and collects wins and awards")
    func week() throws {
        let work = timeGoal(target: 1800)
        let gym = checkInGoal()
        var data = AppData(goals: [work, gym])
        for offset in -6...0 { data.entries.append(LogEntry(goalID: work.id, date: dayOffset(offset, hour: 9), amount: 1800, source: .timer)) }
        data.entries.append(LogEntry(goalID: work.id, date: dayOffset(-9, hour: 9), amount: 3600, source: .timer))
        for offset in [-6, -5, -1] { data.log(1, for: gym.id, at: dayOffset(offset)) }
        data.updateJournal(for: DayID(dayOffset(-2), calendar: testCalendar)) { $0.win = "Shipped it"; $0.mood = .great }
        data.updateJournal(for: DayID(dayOffset(-3), calendar: testCalendar)) { $0.mood = .okay }
        data.achievements = ["first-step": dayOffset(-30), "streak-7": dayOffset(-1)]

        let review = engine(data).weekReview(endingAt: referenceNow)
        #expect(review.focusSeconds == 7 * 1800.0)
        #expect(review.previousFocusSeconds == 3600.0)
        #expect(try #require(review.focusChange) == 2.5)
        #expect(review.perfectDays == 3)
        #expect(review.activeDays == 7)
        #expect(review.wins.map(\.text) == ["Shipped it"])
        #expect(review.averageMood == 4.0)
        #expect(review.achievements.map(\.id) == ["streak-7"])
        let gymWeek = try #require(review.goals.first { $0.goalID == gym.id })
        #expect(gymWeek.met == 3 && gymWeek.due == 7)
    }

    @Test("Year in pixels covers 365 days ending today")
    func pixels() {
        let gym = checkInGoal(createdDaysAgo: 400)
        var data = AppData(goals: [gym])
        data.log(1, for: gym.id, at: referenceNow)
        data.updateJournal(for: DayID(referenceNow, calendar: testCalendar)) { $0.mood = .good }
        let pixels = engine(data).yearInPixels(endingAt: referenceNow)
        #expect(pixels.count == 365)
        #expect(pixels.last?.day == testCalendar.startOfDay(for: referenceNow))
        #expect(pixels.last?.completion == 1.0)
        #expect(pixels.last?.mood == .good)
        #expect(pixels.first?.completion == 0.0)
    }

    @Test("Logged amounts read in what entries count: pages for books, the unit otherwise")
    func loggedUnits() {
        let books = Goal(name: "Read", kind: .books, period: .yearly, target: 12)
        #expect(books.formatLogged(157) == "157 pages")
        #expect(books.formatLogged(1) == "1 page")
        #expect(checkInGoal().formatLogged(3) == "3 workouts")
        #expect(timeGoal().formatLogged(5400) == "1h 30m")
    }
}
