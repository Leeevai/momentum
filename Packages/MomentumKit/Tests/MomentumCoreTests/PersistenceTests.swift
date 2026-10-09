import Foundation
import Testing
@testable import MomentumCore

@Suite("Persistence")
struct PersistenceTests {
    @Test("Version 1 files migrate: goals, per-day totals and the running session")
    func migratesV1() throws {
        let url = try #require(Bundle.module.url(forResource: "v1-data", withExtension: "json", subdirectory: "Fixtures"))
        let data = try FileStore.decode(Data(contentsOf: url))
        #expect(data.version == AppData.currentVersion)
        #expect(data.goals.count == 2)

        let deepWork = try #require(data.goals.first { $0.name == "Deep work" })
        #expect(deepWork.kind == .time)
        #expect(deepWork.target == 3600)
        #expect(deepWork.weekdays == Set(2...6))
        #expect(deepWork.icon == "💻")

        let gym = try #require(data.goals.first { $0.name == "Gym" })
        #expect(gym.kind == .count)
        #expect(gym.unit == "check-ins")

        #expect(data.entries.filter { $0.goalID == deepWork.id }.map(\.amount).sorted() == [1800, 3600])
        #expect(data.entries.filter { $0.goalID == gym.id }.count == 1)
        #expect(data.session?.goalID == deepWork.id)
        #expect(data.session?.isRunning == true)
    }

    @Test("Current files round-trip unchanged")
    func roundTrip() throws {
        var data = AppData.demo(now: referenceNow, calendar: testCalendar)
        data.startFocus(on: data.goals[0].id, planned: 1500, at: referenceNow, calendar: testCalendar)
        data.pauseFocus(at: referenceNow.addingTimeInterval(300))
        let decoded = try FileStore.decode(FileStore.encode(data))
        #expect(decoded == data)
    }

    @Test("Fields missing from older or newer files fall back to defaults")
    func tolerantDecoding() throws {
        let json = """
        {"version": 2, "goals": [{"id": "33333333-3333-3333-3333-333333333333", "name": "Minimal", "kind": "amount", "target": 5}]}
        """
        let data = try FileStore.decode(Data(json.utf8))
        let goal = try #require(data.goals.first)
        #expect(goal.period == .daily)
        #expect(goal.links.isEmpty)
        #expect(goal.quickAddStep == GoalKind.amount.defaultStep)
        #expect(data.entries.isEmpty)
        #expect(data.preferences == Preferences())
    }

    @Test("The file store applies updates on top of what is on disk")
    func fileStoreUpdates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileStore(fileURL: folder.appendingPathComponent("data.json"))
        #expect(store.load().goals.isEmpty)

        let goal = Goal(name: "Persisted", target: 60)
        store.update { $0.upsert(goal) }
        store.update { $0.log(30, for: goal.id) }

        let reloaded = FileStore(fileURL: store.fileURL).load()
        #expect(reloaded.goals.map(\.name) == ["Persisted"])
        #expect(reloaded.entries.count == 1)
    }

    @Test("An unreadable file is backed up rather than overwritten")
    func corruptFileIsKept() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("data.json")
        try Data("not json".utf8).write(to: file)

        let store = FileStore(fileURL: file)
        #expect(store.load().goals.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("unreadable") }
        #expect(backups.count == 1)
    }

    @Test("CSV quotes fields that need it")
    func csvEscaping() {
        #expect(CSVExporter.escape("plain") == "plain")
        #expect(CSVExporter.escape("a, b") == "\"a, b\"")
        #expect(CSVExporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExporter.escape("two\nlines") == "\"two\nlines\"")
    }

    @Test("CSV has one row per entry, with minutes for time goals")
    func csvRows() {
        let goal = Goal(name: "Focus, deep", kind: .time, target: 3600)
        var data = AppData(goals: [goal])
        data.log(1800, for: goal.id, at: referenceNow, note: "Draft")
        let lines = CSVExporter.csv(for: data).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[1].contains("\"Focus, deep\""))
        #expect(lines[1].contains("30.00,minutes,30m,manual,,Draft"))
    }
}

@Suite("Migration safety")
struct MigrationSafetyTests {
    @Test("Reading an old file keeps one untouched copy beside it")
    func keepsLegacyCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(forResource: "v1-data", withExtension: "json", subdirectory: "Fixtures"))
        let file = folder.appendingPathComponent("data.json")
        try FileManager.default.copyItem(at: fixture, to: file)

        let store = FileStore(fileURL: file)
        #expect(store.load().goals.count == 2)
        #expect(store.load().goals.count == 2)
        store.update { $0.log(60, for: $0.goals[0].id) }

        let copy = folder.appendingPathComponent("data.v1-backup.json")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: fixture))
        #expect(FileStore.isLegacy(try Data(contentsOf: file)) == false)
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("backup") }
        #expect(backups == ["data.v1-backup.json"])
    }
}

@Suite("Daily backups")
struct DailyBackupTests {
    @Test("One backup per day, newest kept, oldest pruned")
    func rotation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileStore(fileURL: folder.appendingPathComponent("data.json"))
        #expect(store.backUpDaily(now: referenceNow, calendar: testCalendar) == nil)

        store.update { $0.upsert(Goal(name: "Backed up", target: 1)) }
        for offset in 0..<5 {
            store.backUpDaily(keep: 3, now: dayOffset(offset), calendar: testCalendar)
        }
        #expect(store.backUpDaily(keep: 3, now: dayOffset(4), calendar: testCalendar) == nil)

        let names = try store.dailyBackups().map(\.lastPathComponent)
        #expect(names == ["data-2026-10-12.json", "data-2026-10-11.json", "data-2026-10-10.json"])
        let restored = try FileStore.decode(Data(contentsOf: store.dailyBackups()[0]))
        #expect(restored.goals.map(\.name) == ["Backed up"])
    }
}

@Suite("Write tracking")
struct WriteTrackingTests {
    @Test("Changes and loads report the file's date from inside the coordinator")
    func reportsModification() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("data.json")
        let mine = FileStore(fileURL: file)
        let theirs = FileStore(fileURL: file)

        let own = try #require(mine.transform { $0.upsert(Goal(name: "Mine", target: 1)) }.modification)
        #expect(mine.loadSnapshot().modification == own)

        Thread.sleep(forTimeInterval: 0.01)
        theirs.update { $0.upsert(Goal(name: "Theirs", target: 1)) }
        let snapshot = mine.loadSnapshot()
        #expect(snapshot.modification != own)
        #expect(snapshot.data.goals.count == 2)
    }

    @Test("A change that changes nothing doesn't rewrite the file")
    func unchangedSkipsWrite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileStore(fileURL: folder.appendingPathComponent("data.json"))
        let first = store.transform { $0.upsert(Goal(name: "Once", target: 1)) }
        Thread.sleep(forTimeInterval: 0.01)
        let second = store.transform { _ in }
        #expect(second.modification == first.modification)
        #expect(second.before == second.after)
    }
}
