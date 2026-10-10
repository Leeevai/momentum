import Foundation
import Testing
@testable import MomentumCore

/// A device's copy of the data, changed the way the app changes it: through the stamper.
private struct Device {
    var data: AppData

    mutating func change(at time: Date, _ body: (inout AppData) -> Void) {
        var after = data
        body(&after)
        if after != data { SyncStamper.stamp(&after, from: data, at: time) }
        data = after
    }

    mutating func sync(with other: AppData) {
        data = SyncMerge.merge(data, other)
    }
}

private func at(_ seconds: Double) -> Date { referenceNow.addingTimeInterval(seconds) }

@Suite("Sync stamps")
struct SyncStampTests {
    @Test("Edits stamp the record, deletions leave a tombstone, and new entries need no stamp")
    func stamps() {
        let goal = checkInGoal()
        var device = Device(data: AppData(goals: [goal]))
        device.change(at: at(1)) { $0.log(1, for: goal.id, at: referenceNow) }
        let entry = device.data.entries[0]
        #expect(device.data.sync.stamps[SyncState.entry(entry.id)] == nil)
        device.change(at: at(2)) { $0.updateGoal(goal.id) { $0.name = "Gym!" } }
        #expect(device.data.sync.stamps[SyncState.goal(goal.id)] == at(2))
        device.change(at: at(3)) { $0.deleteEntry(entry.id) }
        #expect(device.data.sync.tombstones[SyncState.entry(entry.id)] == at(3))
        device.change(at: at(4)) { $0.entries.append(entry) }
        #expect(device.data.sync.stamps[SyncState.entry(entry.id)] == at(4))
        #expect(device.data.sync.tombstones[SyncState.entry(entry.id)] == nil)
    }

    @Test("Saving through the file store stamps the change")
    func fileStoreStamps() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = FileStore(fileURL: folder.appendingPathComponent("data.json"))
        let goal = checkInGoal()
        store.update { $0.upsert(goal) }
        #expect(store.load().sync.stamps[SyncState.goal(goal.id)] != nil)
        let merged = store.transform(stamping: false) { $0.preferences.playsSounds = false }.after
        #expect(merged.sync.stamps[SyncState.preferences] == nil)
    }
}

@Suite("Sync merge")
struct SyncMergeTests {
    @Test("Progress logged on two devices adds up")
    func unionOfEntries() {
        let goal = checkInGoal(target: 2)
        let shared = AppData(goals: [goal])
        var mac = Device(data: shared)
        var phone = Device(data: shared)
        mac.change(at: at(1)) { $0.log(1, for: goal.id, at: referenceNow) }
        phone.change(at: at(2)) { $0.log(1, for: goal.id, at: referenceNow) }
        let merged = SyncMerge.merge(mac.data, phone.data)
        #expect(merged.entries.count == 2)
        #expect(engine(merged).isComplete(goal, now: referenceNow))
    }

    @Test("The later edit of a record wins")
    func lastWriterWins() {
        let goal = checkInGoal()
        let shared = AppData(goals: [goal])
        var mac = Device(data: shared)
        var phone = Device(data: shared)
        mac.change(at: at(5)) { $0.updateGoal(goal.id) { $0.name = "Mac name" } }
        phone.change(at: at(3)) { $0.updateGoal(goal.id) { $0.name = "Phone name" } }
        #expect(SyncMerge.merge(mac.data, phone.data).goals.first?.name == "Mac name")
        #expect(SyncMerge.merge(phone.data, mac.data).goals.first?.name == "Mac name")
    }

    @Test("A delete beats older edits, and a newer edit brings the record back")
    func deletes() {
        let goal = checkInGoal()
        let shared = AppData(goals: [goal])
        var mac = Device(data: shared)
        var phone = Device(data: shared)
        phone.change(at: at(1)) { $0.updateGoal(goal.id) { $0.target = 3 } }
        mac.change(at: at(2)) { $0.deleteGoal(goal.id) }
        #expect(SyncMerge.merge(mac.data, phone.data).goals.isEmpty)
        phone.change(at: at(3)) { $0.updateGoal(goal.id) { $0.target = 4 } }
        #expect(SyncMerge.merge(mac.data, phone.data).goals.first?.target == 4.0)
    }

    @Test("Entries for a goal deleted elsewhere count for nothing, and come back with it")
    func orphans() {
        let goal = checkInGoal()
        let shared = AppData(goals: [goal])
        var mac = Device(data: shared)
        var phone = Device(data: shared)
        mac.change(at: at(1)) { $0.deleteGoal(goal.id) }
        phone.change(at: at(2)) { $0.log(1, for: goal.id, at: referenceNow) }
        let merged = SyncMerge.merge(mac.data, phone.data)
        #expect(merged.goals.isEmpty)
        #expect(ProgressEngine(data: merged, calendar: testCalendar).data.entries.isEmpty)
        // An edit on the phone after the delete brings the goal back, with what was logged.
        phone.change(at: at(3)) { $0.updateGoal(goal.id) { $0.target = 2 } }
        let revived = ProgressEngine(data: SyncMerge.merge(mac.data, phone.data), calendar: testCalendar)
        #expect(revived.data.entries.count == 1)
    }

    @Test("A timer on a goal deleted elsewhere is settled away")
    func orphanTimer() {
        let work = timeGoal()
        let shared = AppData(goals: [work])
        var mac = Device(data: shared)
        var phone = Device(data: shared)
        mac.change(at: at(1)) { $0.deleteGoal(work.id) }
        phone.change(at: at(2)) { $0.startFocus(on: work.id, at: at(2), calendar: testCalendar) }
        var merged = SyncMerge.merge(mac.data, phone.data)
        let changed = merged.settleTimer()
        #expect(changed)
        #expect(merged.session == nil)
        let changedAgain = merged.settleTimer()
        #expect(!changedAgain)
    }

    @Test("The session, preferences and journal take the latest change")
    func singles() {
        let work = timeGoal()
        let shared = AppData(goals: [work])
        var mac = Device(data: shared)
        var phone = Device(data: shared)
        let day = DayID(referenceNow, calendar: testCalendar)
        mac.change(at: at(1)) { $0.startFocus(on: work.id, at: at(1), calendar: testCalendar) }
        phone.change(at: at(2)) { $0.preferences.defaultFocusMinutes = 45 }
        phone.change(at: at(3)) { $0.updateJournal(for: day, at: at(3)) { $0.mood = .good } }
        mac.change(at: at(4)) { $0.updateJournal(for: day, at: at(4)) { $0.mood = .great } }
        let merged = SyncMerge.merge(phone.data, mac.data)
        #expect(merged.session?.goalID == work.id)
        #expect(merged.preferences.defaultFocusMinutes == 45)
        #expect(merged.journalEntry(for: day)?.mood == .great)
    }

    @Test("Achievements keep the earliest date either side earned them")
    func achievements() {
        var a = AppData()
        var b = AppData()
        a.achievements = ["first-step": at(10), "streak-3": at(20)]
        b.achievements = ["first-step": at(5)]
        #expect(SyncMerge.merge(a, b).achievements == ["first-step": at(5), "streak-3": at(20)])
    }

    @Test("Merging is commutative and idempotent")
    func algebra() {
        let goal = checkInGoal()
        let shared = AppData(goals: [goal])
        var mac = Device(data: shared)
        var phone = Device(data: shared)
        mac.change(at: at(1)) { $0.log(1, for: goal.id, at: referenceNow) }
        phone.change(at: at(1)) { $0.updateGoal(goal.id) { $0.name = "Tie" } }
        mac.change(at: at(1)) { $0.updateGoal(goal.id) { $0.name = "Same time" } }
        let ab = SyncMerge.merge(mac.data, phone.data)
        let ba = SyncMerge.merge(phone.data, mac.data)
        #expect(ab == ba)
        #expect(SyncMerge.merge(ab, ab) == ab)
        #expect(SyncMerge.merge(ab, mac.data) == ab)
    }

    @Test("Three devices editing at random converge once they've all synced", arguments: Array(UInt64(1)...40))
    func convergence(seed: UInt64) {
        var random = SeededRandom(seed: seed)
        let goals = (0..<3).map { index in Goal(name: "G\(index)", kind: .count, target: 2) }
            + [Goal(name: "Focus A", kind: .time, target: 3600), Goal(name: "Focus B", kind: .time, target: 3600)]
        var devices = Array(repeating: Device(data: AppData(goals: goals)), count: 3)
        var clock = 0.0
        for _ in 0..<120 {
            clock += 1
            let index = random.next(upTo: 3)
            let time = at(clock)
            switch random.next(upTo: 12) {
            case 9:
                let timeGoals = devices[index].data.goals.filter { $0.kind == .time }
                if let goal = timeGoals.randomElement(using: &random) {
                    devices[index].change(at: time) { $0.startFocus(on: goal.id, at: time) }
                }
            case 10:
                devices[index].change(at: time) { $0.stopFocus(at: time) }
            case 11:
                devices[index].change(at: time) { $0.togglePauseFocus(at: time) }
            case 0, 1, 2:
                if let goal = devices[index].data.goals.randomElement(using: &random) {
                    devices[index].change(at: time) { $0.log(1, for: goal.id, at: time) }
                }
            case 3:
                if let entry = devices[index].data.entries.randomElement(using: &random) {
                    devices[index].change(at: time) { $0.deleteEntry(entry.id) }
                }
            case 4:
                if let goal = devices[index].data.goals.randomElement(using: &random) {
                    devices[index].change(at: time) { $0.updateGoal(goal.id) { $0.target = Double(1 + random.next(upTo: 5)) } }
                }
            case 5:
                devices[index].change(at: time) { $0.upsert(Goal(name: "New \(clock)", kind: .count, target: 1)) }
            case 6:
                if devices[index].data.goals.count > 1, let goal = devices[index].data.goals.randomElement(using: &random) {
                    devices[index].change(at: time) { $0.deleteGoal(goal.id) }
                }
            case 7:
                let day = DayID(time, calendar: testCalendar)
                let mood = Mood(rawValue: 1 + random.next(upTo: 5))
                devices[index].change(at: time) { $0.updateJournal(for: day, at: time) { $0.mood = mood } }
            default:
                let other = random.next(upTo: 3)
                devices[index].sync(with: devices[other].data)
            }
        }
        // Merging is associative: the same three copies in either grouping.
        let (a, b, c) = (devices[0].data, devices[1].data, devices[2].data)
        #expect(SyncMerge.merge(SyncMerge.merge(a, b), c) == SyncMerge.merge(a, SyncMerge.merge(b, c)))
        // Everyone syncs with everyone, twice round.
        for _ in 0..<2 {
            for i in 0..<3 { for j in 0..<3 where i != j { devices[i].sync(with: devices[j].data) } }
        }
        #expect(devices[0].data == devices[1].data)
        #expect(devices[1].data == devices[2].data)
    }
}

@Suite("Sync folder")
struct SyncFolderTests {
    @Test("Each device writes its own file and reads everyone else's")
    func roundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let goal = checkInGoal()
        let mac = SyncFolder(url: folder, deviceID: "mac")
        let phone = SyncFolder(url: folder, deviceID: "phone")
        try mac.write(SyncEnvelope(deviceID: "mac", deviceName: "Studio", platform: "macOS", savedAt: referenceNow, data: AppData(goals: [goal])))
        try phone.write(SyncEnvelope(deviceID: "phone", deviceName: "iPhone", platform: "iOS", savedAt: referenceNow, data: AppData()))
        try Data("not json".utf8).write(to: folder.appendingPathComponent("broken.momentum-sync"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let seenByPhone = phone.readPeers()
        #expect(seenByPhone.map(\.deviceName) == ["Studio"])
        #expect(seenByPhone.first?.data.goals.map(\.id) == [goal.id])
        #expect(mac.readPeers().map(\.deviceID) == ["phone"])
        #expect(mac.peerFiles().count == 2)
    }

    @Test("A file in a newer data format is left out, with the device it came from")
    func newerFormatLeftOut() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("mac.momentum-sync")
        let saved = referenceNow.timeIntervalSinceReferenceDate
        let newer = #"{"deviceID":"mac","deviceName":"Studio","platform":"macOS","savedAt":\#(saved),"data":{"version":3,"goals":[],"entries":[]}}"#
        try Data(newer.utf8).write(to: file)

        let phone = SyncFolder(url: folder, deviceID: "phone")
        let read = phone.read(file, now: referenceNow)
        let device: String? = switch read {
        case .newer(let name): name
        default: nil
        }
        let peers = phone.readPeers(now: referenceNow, startingFresh: true)
        #expect(device == "Studio")
        #expect(peers.isEmpty)
    }
}
