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

    @Test("Unknown colors and book statuses from newer versions fall back")
    func tolerantEnums() throws {
        let json = #"{"version": 2, "goals": [{"name": "G", "kind": "books", "target": 1, "color": "ultraviolet", "books": [{"title": "B", "status": "lent"}]}]}"#
        let goal = try #require(FileStore.decode(Data(json.utf8)).goals.first)
        #expect(goal.color == .blue)
        #expect(goal.books.first?.status == .wantToRead)
    }

    @Test("An entry with a source from a newer version reads as manual instead of failing the file")
    func tolerantEntrySource() throws {
        let goal = UUID()
        let json = #"""
        {"version": 2, "goals": [{"id": "\#(goal.uuidString)", "name": "Reading", "kind": "time", "target": 1800}],
         "entries": [{"goalID": "\#(goal.uuidString)", "date": 813254400, "amount": 60, "source": "health"},
                     {"goalID": "\#(goal.uuidString)", "date": 813254460, "amount": 600, "source": "timer"}]}
        """#
        let data = try FileStore.decode(Data(json.utf8))
        let sources = data.entries.map(\.source)
        let amounts = data.entries.map(\.amount)
        #expect(sources == [.manual, .timer])
        #expect(amounts == [60, 600])
    }

    @Test("Focus sounds default to off, and unknown ones from newer versions don't break the file")
    func focusSoundDecoding() throws {
        let json = #"{"version": 2, "preferences": {"focusSound": "ocean", "focusSoundVolume": 3}}"#
        let preferences = try FileStore.decode(Data(json.utf8)).preferences
        #expect(preferences.focusSound == .off)
        #expect(preferences.focusSoundVolume == 1)
    }

    @Test("A session keeps the time zone it started in; one saved without it, or with a bad one, still reads")
    func sessionTimeZone() throws {
        let goal = timeGoal()
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        let saved = try FileStore.decode(FileStore.encode(data)).session?.timeZone
        #expect(saved == "America/Chicago")

        let older = #"{"version": 2, "session": {"goalID": "\#(goal.id.uuidString)", "runningSince": 813254400}}"#
        let bad = #"{"version": 2, "session": {"goalID": "\#(goal.id.uuidString)", "runningSince": 813254400, "timeZone": 5}}"#
        let olderSession = try #require(FileStore.decode(Data(older.utf8)).session)
        let badSession = try #require(FileStore.decode(Data(bad.utf8)).session)
        #expect(olderSession.timeZone == nil)
        #expect(badSession.timeZone == nil)
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
        #expect(store.isUnreadable)
        // Changes aren't saved over it, and reading it again keeps just the one copy.
        let result = store.transform { $0.upsert(Goal(name: "New", target: 1)) }
        #expect(result.after.goals.isEmpty)
        #expect(try Data(contentsOf: file) == Data("not json".utf8))
        _ = store.load()
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains("unreadable") }
        #expect(backups.count == 1)

        // A restored copy or an import still replaces it.
        store.replace(with: AppData(goals: [Goal(name: "Restored", target: 1)]))
        #expect(!store.isUnreadable)
        #expect(FileStore(fileURL: file).load().goals.map(\.name) == ["Restored"])
    }

    @Test("A file in a newer data format is refused, and nothing is saved over it")
    func newerFormatIsKept() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("data.json")
        // Readable as this version's data, but without what the newer version keeps elsewhere.
        let newer = Data(#"{"version":3,"goals":[{"name":"Read","kind":"books","target":12}],"entries":[],"logs":[{"pages":40}]}"#.utf8)
        try newer.write(to: file)

        #expect(throws: FileStore.FormatError.newerVersion(3)) { try FileStore.decode(newer) }
        let store = FileStore(fileURL: file)
        let result = store.transform { $0.upsert(Goal(name: "New", target: 1)) }
        let unreadable = store.isUnreadable
        let saved = try Data(contentsOf: file)
        #expect(result.after.goals.isEmpty)
        #expect(unreadable)
        #expect(saved == newer)
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

    @Test("A file that can't be read isn't kept as a day's copy, so the good copies stay")
    func noDailyCopyOfUnreadableFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileStore(fileURL: folder.appendingPathComponent("data.json"))
        store.update { $0.upsert(Goal(name: "Backed up", target: 1)) }
        store.backUpDaily(keep: 1, now: dayOffset(0), calendar: testCalendar)
        try Data("not json".utf8).write(to: store.fileURL)
        // A date of its own, so the store can't take it for the version it wrote.
        try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: store.fileURL.path)

        let written = store.backUpDaily(keep: 1, now: dayOffset(1), calendar: testCalendar)
        let names = try store.dailyBackups().map(\.lastPathComponent)
        #expect(written == nil)
        #expect(names == ["data-2026-10-08.json"])
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

@Suite("Out-of-range amounts")
struct AmountLimitTests {
    @Test("Amounts that aren't numbers or are beyond any real one are refused, and display never traps")
    func limits() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        #expect(data.log(.infinity, for: goal.id) == nil)
        #expect(data.log(.nan, for: goal.id) == nil)
        #expect(data.log(1e300, for: goal.id) == nil)
        #expect(data.log(5, for: goal.id) != nil)
        #expect(Formatting.duration(1e300) == Formatting.duration(1e15 * 60))
        #expect(Formatting.duration(.nan) == "0m")
        #expect(Formatting.clock(.infinity) == "0:00")
    }
}
