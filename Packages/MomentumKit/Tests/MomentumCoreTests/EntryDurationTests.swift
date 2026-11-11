import Foundation
import Testing
@testable import MomentumCore

@Suite("How long an entry took")
struct EntryDurationTests {
    @Test("An entry from before durations reads with none; a bad one is dropped, not the entry")
    func olderAndBadFiles() throws {
        let json = """
        {"version": 2, "goals": [{"id": "33333333-3333-3333-3333-333333333333", "name": "Gym", "kind": "count", "target": 1}],
         "entries": [
          {"id": "44444444-4444-4444-4444-444444444444", "goalID": "33333333-3333-3333-3333-333333333333", "date": 800000000, "amount": 1},
          {"id": "55555555-5555-5555-5555-555555555555", "goalID": "33333333-3333-3333-3333-333333333333", "date": 800000100, "amount": 1, "duration": -60},
          {"id": "66666666-6666-6666-6666-666666666666", "goalID": "33333333-3333-3333-3333-333333333333", "date": 800000200, "amount": 1, "duration": "long"}
         ]}
        """
        let entries = try FileStore.decode(Data(json.utf8)).entries
        let durations = entries.map(\.duration)
        #expect(entries.count == 3)
        #expect(durations == [nil, nil, nil])
    }

    @Test("A duration survives a save, and is left out when there's none")
    func roundTrip() throws {
        let gym = checkInGoal()
        var data = AppData(goals: [gym])
        data.entries = [LogEntry(goalID: gym.id, date: referenceNow, amount: 1, duration: 45 * 60),
                        LogEntry(goalID: gym.id, date: referenceNow.addingTimeInterval(60), amount: 1)]
        let encoded = try FileStore.encode(data)
        let reread = try FileStore.decode(encoded).entries.map(\.duration)
        let plain = String(decoding: try JSONEncoder().encode(LogEntry(goalID: gym.id, date: referenceNow, amount: 1)), as: UTF8.self)
        #expect(reread == [2700, nil])
        #expect(!plain.contains("duration"))
    }

    @Test("Durations are kept on amounts and counts, followed or not, never on time")
    func whereKept() {
        let gym = checkInGoal()
        let work = timeGoal()
        let run = Goal(name: "Run", kind: .amount, unit: "km", target: 5)
        var course = Goal(name: "Course", kind: .amount, unit: "lessons", target: 3)
        course.books = [Book(title: "Swift", totalPages: 10, status: .reading, startedAt: referenceNow)]
        var data = AppData(goals: [gym, work, run, course])
        data.log(1, for: gym.id, at: referenceNow, duration: 1800)
        data.log(1800, for: work.id, at: referenceNow, duration: 1800)
        data.logReading(5, for: run.id, at: referenceNow, duration: 1680)
        data.logReading(1, for: course.id, at: referenceNow, duration: 1200)
        data.log(1, for: gym.id, at: referenceNow, duration: .infinity)
        let durations = data.entries.map(\.duration)
        #expect(durations == [1800, nil, 1680, 1200, nil])
    }
}

@Suite("Durations and followed items elsewhere")
struct DurationElsewhereTests {
    @Test("A duration set straight on an entry that isn't a number doesn't stop the save")
    func nonFiniteSaves() throws {
        let gym = checkInGoal()
        var entry = LogEntry(goalID: gym.id, date: referenceNow, amount: 1)
        entry.duration = .nan
        let data = AppData(goals: [gym], entries: [entry])
        let reread = try FileStore.decode(FileStore.encode(data)).entries.first
        #expect(reread != nil)
        #expect(reread?.duration == nil)
    }

    @Test("The CSV export has each entry's duration in minutes, in a column at the end")
    func csv() {
        let gym = checkInGoal()
        var data = AppData(goals: [gym])
        data.log(1, for: gym.id, at: referenceNow, duration: 45 * 60)
        data.log(1, for: gym.id, at: referenceNow.addingTimeInterval(60))
        let lines = CSVExporter.csv(for: data).split(separator: "\n").map { $0.split(separator: ",", omittingEmptySubsequences: false) }
        let lastColumns = lines.map { $0.last.map(String.init) ?? "?" }
        #expect(lastColumns == ["duration_minutes", "45.00", ""])
    }

    @Test("Insights count finished books, not finished courses")
    func insights() {
        var course = Goal(name: "Course", kind: .amount, unit: "lessons", target: 3,
                          createdAt: testCalendar.date(byAdding: .day, value: -30, to: referenceNow)!)
        course.books = [Book(title: "Swift", totalPages: 10, currentPage: 10, status: .finished, finishedAt: dayOffset(-1))]
        var reading = Goal(name: "Read", kind: .books, target: 12,
                           createdAt: testCalendar.date(byAdding: .day, value: -30, to: referenceNow)!)
        reading.books = [Book(title: "Dune", totalPages: 400, currentPage: 400, status: .finished, finishedAt: dayOffset(-1))]
        let finished = engine(AppData(goals: [course, reading])).insights(days: 7, now: referenceNow).booksFinished
        #expect(finished == 1)
    }
}
