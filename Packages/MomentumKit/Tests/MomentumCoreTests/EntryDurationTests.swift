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
}
