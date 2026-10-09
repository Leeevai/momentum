import Foundation
import Testing
@testable import MomentumCore

/// Regressions found in the review of sync, Pomodoro, achievements and the fast paths.
@Suite("Review fixes, 2.0")
struct SyncReviewFixTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A restored backup keeps its history through the next sync")
    func restoreSurvivesSync() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(fileURL: dir.appendingPathComponent("data.json"))
        let goal = checkInGoal()
        store.update { data in
            data.upsert(goal)
            for offset in -20...(-1) { data.log(1, for: goal.id, at: dayOffset(offset)) }
        }
        let backup = store.load()
        store.update { $0.deleteGoal(goal.id) }
        // Another device already has the deletion.
        let peer = store.load()
        Thread.sleep(forTimeInterval: 0.01)
        let restored = store.replace(with: backup).data
        let merged = SyncMerge.merge(restored, peer)
        #expect(merged.goal(goal.id) != nil)
        #expect(merged.entries.filter { $0.goalID == goal.id }.count == 20)
    }

    @Test("Two devices finishing the same block log it once")
    func blockLoggedOnce() {
        let goal = timeGoal()
        var data = AppData(goals: [goal])
        data.preferences.pomodoro.isEnabled = true
        data.toggleFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        var mac = data
        var phone = data
        mac.advancePomodoro(at: referenceNow.addingTimeInterval(1500), calendar: testCalendar)
        phone.advancePomodoro(at: referenceNow.addingTimeInterval(2400), calendar: testCalendar)
        let merged = SyncMerge.merge(mac, phone)
        #expect(merged.entries.count == 1)
        #expect(merged.entries.first?.amount == 1500.0)
    }

    @Test("A session from one device and a break from another are never both kept")
    func timerMergesWhole() {
        let first = timeGoal()
        let second = Goal(name: "Spanish", kind: .time, target: 900)
        var data = AppData(goals: [first, second])
        data.preferences.pomodoro.isEnabled = true
        data.toggleFocus(on: first.id, at: referenceNow, calendar: testCalendar)
        var a = data
        var b = data
        var before = a
        a.advancePomodoro(at: referenceNow.addingTimeInterval(1500), calendar: testCalendar)
        SyncStamper.stamp(&a, from: before, at: referenceNow.addingTimeInterval(1500))
        before = b
        b.toggleFocus(on: second.id, at: referenceNow.addingTimeInterval(1800), calendar: testCalendar)
        SyncStamper.stamp(&b, from: before, at: referenceNow.addingTimeInterval(1800))
        let merged = SyncMerge.merge(a, b)
        #expect(merged.session?.goalID == second.id)
        #expect(merged.rest == nil)
        #expect(SyncMerge.merge(b, a).session?.goalID == second.id)
    }

    @Test("Files from devices gone for months are not merged")
    func stalePeersIgnored() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = SyncFolder(url: dir, deviceID: "old")
        try old.write(SyncEnvelope(deviceID: "old", deviceName: "Old iPhone", platform: "iOS",
                                   savedAt: referenceNow.addingTimeInterval(-160 * 86_400), data: AppData(goals: [checkInGoal()])))
        let mac = SyncFolder(url: dir, deviceID: "mac")
        #expect(mac.readPeers(now: referenceNow).isEmpty)
        #expect(mac.readPeers(now: referenceNow.addingTimeInterval(-30 * 86_400)).count == 1)
    }

    @Test("Dates survive a save exactly, so undo matches a session after another process writes")
    func exactDates() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("data.json")
        let app = FileStore(fileURL: url)
        let widget = FileStore(fileURL: url)
        let goal = timeGoal()
        let start = Date(timeIntervalSince1970: 1_791_561_600.734_512)
        let transform = app.transform { data in
            data.upsert(goal)
            data.startFocus(on: goal.id, at: start, calendar: testCalendar)
        }
        widget.update { $0.preferences.playsSounds = false }
        var reread = app.load()
        #expect(reread.session?.startedAt == start)
        DataPatch(from: transform.before, to: transform.after).undo(on: &reread)
        #expect(reread.session == nil)
        // Files from before 2.0, with ISO 8601 dates, still read.
        let legacy = #"{"version":2,"goals":[],"entries":[],"journal":[{"day":"2026-10-08","modifiedAt":"2026-10-08T12:00:00Z"}]}"#
        #expect(try FileStore.decode(Data(legacy.utf8)).journal.first?.modifiedAt == date(2026, 10, 8, 7))
    }

    @Test("Moving entries between days refreshes a cached streak")
    func fingerprintSeesMovedDays() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        data.log(1, for: goal.id, at: dayOffset(-7))
        data.log(1, for: goal.id, at: dayOffset(-4))
        #expect(engine(data).streak(for: goal, now: referenceNow).best == 1)
        data.entries[0].date = dayOffset(-6)
        data.entries[1].date = dayOffset(-5)
        #expect(engine(data).streak(for: goal, now: referenceNow).best == 2)
    }

    @Test("Undoing a journal edit keeps the day's other changes")
    func journalUndoByField() {
        var data = AppData()
        let day = DayID(referenceNow, calendar: testCalendar)
        let before = data
        data.updateJournal(for: day) { $0.intention = "Ship it" }
        let after = data
        data.updateJournal(for: day) { $0.mood = .great }
        DataPatch(from: before, to: after).undo(on: &data)
        #expect(data.journalEntry(for: day)?.intention == "")
        #expect(data.journalEntry(for: day)?.mood == .great)
    }

    @Test("Undoing a skipped break doesn't bring it back over a session started since")
    func breakUndoKeepsSession() {
        let goal = timeGoal()
        var data = AppData(goals: [goal])
        data.preferences.pomodoro.isEnabled = true
        data.toggleFocus(on: goal.id, at: referenceNow, calendar: testCalendar)
        data.advancePomodoro(at: referenceNow.addingTimeInterval(1500), calendar: testCalendar)
        let before = data
        data.endRest()
        let after = data
        data.startFocus(on: goal.id, at: referenceNow.addingTimeInterval(1600), calendar: testCalendar)
        DataPatch(from: before, to: after).undo(on: &data)
        #expect(data.session != nil)
        #expect(data.rest == nil)
    }

    @Test("Finishing books on dates far apart isn't a comeback")
    func comebackNeedsLogs() {
        let finished = [date(2025, 1, 10), date(2025, 3, 2)].map { Book(title: "B", totalPages: 100, currentPage: 100, status: .finished, finishedAt: $0) }
        let goal = Goal(name: "Read", kind: .books, period: .yearly, target: 12, books: finished, createdAt: date(2024, 12, 1))
        let value = engine(AppData(goals: [goal])).achievements(now: referenceNow).first { $0.id == "comeback" }?.value
        #expect(value == 0.0)
    }

    @Test("Weekends off don't break a flawless week of weekday goals")
    func flawlessWeekdays() {
        let goal = checkInGoal(weekdays: Set(2...6), createdDaysAgo: 30)
        var data = AppData(goals: [goal])
        for offset in -20...0 where testCalendar.component(.weekday, from: dayOffset(offset)) != 1 && testCalendar.component(.weekday, from: dayOffset(offset)) != 7 {
            data.log(1, for: goal.id, at: dayOffset(offset))
        }
        let value = engine(data).achievements(now: referenceNow).first { $0.id == "perfect-week" }?.value ?? 0
        #expect(value >= 14)
    }

    @Test("A session's after-midnight piece doesn't make a night owl")
    func midnightPiece() {
        let goal = timeGoal()
        var data = AppData(goals: [goal])
        data.startFocus(on: goal.id, at: dayOffset(-1, hour: 22), calendar: testCalendar)
        data.stopFocus(at: dayOffset(0, hour: 0).addingTimeInterval(30 * 60), calendar: testCalendar)
        #expect(data.entries.count == 2)
        let value = engine(data).achievements(now: referenceNow).first { $0.id == "night-owl" }?.value
        #expect(value == 0.0)
    }

    @Test("A deleted goal doesn't hold one of the three priorities")
    func deletedPriority() {
        let goals = (0..<4).map { Goal(name: "G\($0)", kind: .count, target: 1) }
        var data = AppData(goals: goals)
        let day = DayID(referenceNow, calendar: testCalendar)
        for goal in goals.prefix(3) { data.togglePriority(goal.id, on: day) }
        data.deleteGoal(goals[2].id)
        data.togglePriority(goals[3].id, on: day)
        #expect(data.journalEntry(for: day)?.priorities == [goals[0].id, goals[1].id, goals[3].id])
    }

    @Test("Backups are named in the Gregorian calendar whatever the device uses")
    func gregorianBackupNames() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = FileStore(fileURL: dir.appendingPathComponent("data.json"))
        store.update { $0.upsert(checkInGoal()) }
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = testCalendar.timeZone
        let written = try #require(store.backUpDaily(now: referenceNow, calendar: japanese))
        #expect(written.lastPathComponent == "data-2026-10-08.json")
    }
}
