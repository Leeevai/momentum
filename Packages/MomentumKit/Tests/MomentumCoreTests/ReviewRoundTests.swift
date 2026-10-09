import Foundation
import Testing
@testable import MomentumCore

/// Fixes from reviewing challenges, session ratings and the associative merge.
@Suite("Review fixes: challenges and timer handoff")
struct ReviewRoundTests {
    private func stamped(_ data: inout AppData, at seconds: Double, _ change: (inout AppData) -> Void) {
        let before = data
        change(&data)
        SyncStamper.stamp(&data, from: before, at: referenceNow.addingTimeInterval(seconds))
    }

    private func time(_ seconds: Double) -> Date { referenceNow.addingTimeInterval(seconds) }

    @Test("Undo takes back a challenge started, changed or ended")
    func undoChallenge() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        let before = data
        data.startChallenge(on: goal.id, days: 30, from: DayID(referenceNow, calendar: testCalendar))
        DataPatch(from: before, to: data).undo(on: &data)
        #expect(data.goal(goal.id)?.challenge == nil)
    }

    @Test("Undo reverts every field of a goal")
    func revertCoversEveryField() {
        let original = checkInGoal()
        var changed = original
        changed.name = "Swim"
        changed.icon = "🏊"
        changed.symbol = "figure.pool.swim"
        changed.color = .teal
        changed.category = "Fitness"
        changed.details = "Laps"
        changed.kind = .amount
        changed.unit = "laps"
        changed.period = .weekly
        changed.target = 40
        changed.streakMinimum = 10
        changed.weekdays = [2, 4]
        changed.deadline = referenceNow
        changed.quickAddStep = 5
        changed.focusMinutes = 30
        changed.links = [GoalLink(title: "Pool", url: URL(string: "https://example.com")!)]
        changed.milestones = [Milestone(title: "1 km")]
        changed.books = [Book(title: "Swimming", author: "A", totalPages: 100, addedAt: referenceNow)]
        changed.reminder = ReminderSchedule()
        changed.stackAfter = UUID()
        changed.breaks = [DateInterval(start: referenceNow, duration: 3600)]
        changed.challenge = Challenge(start: DayID(year: 2026, month: 10, day: 1), days: 7)
        changed.createdAt = referenceNow.addingTimeInterval(-1)
        changed.archivedAt = referenceNow

        // Every stored property must differ, so a field added later and left out of `revert`
        // fails here.
        let same = zip(Mirror(reflecting: original).children, Mirror(reflecting: changed).children)
            .filter { String(describing: $0.value) == String(describing: $1.value) }
            .compactMap(\.0.label)
        #expect(same == ["id"])

        var reverted = changed
        reverted.revert(to: original, from: changed)
        #expect(reverted == original)
    }

    @Test("A challenge spent entirely on a break isn't won")
    func notWonOnBreak() throws {
        var goal = checkInGoal()
        goal.breaks = [DateInterval(start: dayOffset(-10, hour: 0), end: dayOffset(2, hour: 0))]
        var data = AppData(goals: [goal])
        data.startChallenge(on: goal.id, days: 7, from: DayID(dayOffset(-7), calendar: testCalendar))
        let engine = engine(data)
        let stored = try #require(engine.goal(goal.id))
        let status = try #require(engine.challengeStatus(for: stored, now: referenceNow))
        #expect(status.isFinished)
        #expect(!status.isWon)
        #expect(!engine.newlyEarnedAchievements(now: referenceNow).contains { $0.id == "challenge-7" })
    }

    @Test("A challenge length read from a file is kept within bounds")
    func clampedLength() throws {
        let negative = try JSONDecoder().decode(Challenge.self, from: Data(#"{"start":"2026-10-01","days":-3}"#.utf8))
        #expect(negative.days == 1)
        let huge = try JSONDecoder().decode(Challenge.self, from: Data(#"{"start":"2026-10-01","days":99999999}"#.utf8))
        #expect(huge.days == Challenge.maximumDays)
    }

    @Test("A duplicated goal starts without the original's challenge")
    func duplicateDropsChallenge() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        data.startChallenge(on: goal.id, days: 30, from: DayID(referenceNow, calendar: testCalendar))
        let copy = data.duplicateGoal(goal.id, at: referenceNow)
        #expect(copy?.challenge == nil)
    }

    @Test("A session the other device never saw survives that device stopping an older one")
    func unseenSessionSurvives() {
        let reading = timeGoal(minutes: nil)
        var writing = timeGoal(minutes: nil)
        writing.name = "Writing"
        var mac = AppData(goals: [reading, writing])
        stamped(&mac, at: 0) { $0.startFocus(on: writing.id, at: time(0), calendar: testCalendar) }
        var phone = mac
        // The phone starts reading; the Mac, not having heard, stops writing later.
        stamped(&phone, at: 100) { $0.startFocus(on: reading.id, at: time(100), calendar: testCalendar) }
        stamped(&mac, at: 1900) { $0.stopFocus(at: time(1900), calendar: testCalendar) }

        var merged = SyncMerge.merge(phone, mac)
        #expect(merged.session == nil)
        let changed = merged.settleAfterMerge(from: phone, calendar: testCalendar)
        #expect(changed)
        #expect(merged.session?.goalID == reading.id)
    }

    @Test("A session stopped on another device stays stopped")
    func stoppedElsewhereStaysStopped() {
        let reading = timeGoal(minutes: nil)
        var phone = AppData(goals: [reading])
        stamped(&phone, at: 0) { $0.startFocus(on: reading.id, at: time(0), calendar: testCalendar) }
        var mac = phone
        stamped(&mac, at: 1200) { $0.stopFocus(at: time(1200), calendar: testCalendar) }

        var merged = SyncMerge.merge(phone, mac)
        let changed = merged.settleAfterMerge(from: phone, calendar: testCalendar)
        #expect(!changed)
        #expect(merged.session == nil)
        #expect(merged.entries.map(\.amount) == [1200])
    }

    @Test("A session replaced by one started elsewhere ends there, its time saved")
    func replacedSessionIsSaved() {
        let reading = timeGoal(minutes: nil)
        var writing = timeGoal(minutes: nil)
        writing.name = "Writing"
        let shared = AppData(goals: [reading, writing])
        var phone = shared
        var mac = shared
        stamped(&phone, at: 0) { $0.startFocus(on: reading.id, at: time(0), calendar: testCalendar) }
        stamped(&mac, at: 1800) { $0.startFocus(on: writing.id, at: time(1800), calendar: testCalendar) }

        var merged = SyncMerge.merge(phone, mac)
        #expect(merged.session?.goalID == writing.id)
        merged.settleAfterMerge(from: phone, calendar: testCalendar)
        #expect(merged.session?.goalID == writing.id)
        #expect(merged.entries.filter { $0.goalID == reading.id }.map(\.amount) == [1800])
    }

    @Test("A session started after the one a merge brings back keeps running, and the older one ends")
    func laterSessionWins() {
        let reading = timeGoal(minutes: nil)
        var writing = timeGoal(minutes: nil)
        writing.name = "Writing"
        var mac = AppData(goals: [reading, writing])
        stamped(&mac, at: 0) { $0.startFocus(on: writing.id, at: time(0), calendar: testCalendar) }
        var phone = mac
        // The phone moves on to reading; the Mac, not having heard, pauses writing later.
        stamped(&phone, at: 1000) { $0.startFocus(on: reading.id, at: time(1000), calendar: testCalendar) }
        stamped(&mac, at: 1500) { $0.pauseFocus(at: time(1500)) }

        var onPhone = SyncMerge.merge(phone, mac)
        #expect(onPhone.session?.goalID == writing.id)
        onPhone.settleAfterMerge(from: phone, at: time(1600), calendar: testCalendar)
        #expect(onPhone.session?.goalID == reading.id)
        // Writing was logged once, up to where reading began.
        #expect(onPhone.entries.filter { $0.goalID == writing.id }.map(\.amount) == [1000])

        // The Mac, merging the phone's settled copy, stops showing writing too.
        var settled = onPhone
        SyncStamper.stamp(&settled, from: SyncMerge.merge(phone, mac), at: time(1600))
        var onMac = SyncMerge.merge(mac, settled)
        onMac.settleAfterMerge(from: mac, at: time(1700), calendar: testCalendar)
        #expect(onMac.session?.goalID == reading.id)
    }

    @Test("A session the merge replaced with an older one that a third device never ended stops it there")
    func olderUnendedSessionStops() {
        let reading = timeGoal(minutes: nil)
        var writing = timeGoal(minutes: nil)
        writing.name = "Writing"
        let shared = AppData(goals: [reading, writing])
        var mac = shared
        var phone = shared
        stamped(&mac, at: 0) { $0.startFocus(on: writing.id, at: time(0), calendar: testCalendar) }
        // The phone never saw writing; it starts reading later, then the Mac edits writing's note.
        stamped(&phone, at: 1000) { $0.startFocus(on: reading.id, at: time(1000), calendar: testCalendar) }
        stamped(&mac, at: 1500) { $0.session?.note = "Chapter two" }

        var merged = SyncMerge.merge(phone, mac)
        merged.settleAfterMerge(from: phone, at: time(1600), calendar: testCalendar)
        #expect(merged.session?.goalID == reading.id)
        #expect(merged.entries.filter { $0.goalID == writing.id }.map(\.amount) == [1000])
        #expect(merged.sync.endedSessions[SyncState.sessionKey(SyncMerge.merge(phone, mac).session!)] != nil)
    }

    @Test("A session brought back by an undo isn't lost when another device starts one")
    func undoneStopSurvives() {
        let reading = timeGoal(minutes: nil)
        var writing = timeGoal(minutes: nil)
        writing.name = "Writing"
        var phone = AppData(goals: [reading, writing])
        stamped(&phone, at: 0) { $0.startFocus(on: reading.id, at: time(0), calendar: testCalendar) }
        let running = phone
        stamped(&phone, at: 1000) { $0.stopFocus(at: time(1000), calendar: testCalendar) }
        var mac = SyncMerge.merge(AppData(goals: [reading, writing]), phone)
        // The phone undoes the stop; the Mac, not having seen that, starts writing.
        let stopped = phone
        stamped(&phone, at: 1100) { data in DataPatch(from: running, to: stopped).undo(on: &data) }
        #expect(phone.session?.goalID == reading.id)
        stamped(&mac, at: 2000) { $0.startFocus(on: writing.id, at: time(2000), calendar: testCalendar) }

        var onPhone = SyncMerge.merge(phone, mac)
        onPhone.settleAfterMerge(from: phone, at: time(2100), calendar: testCalendar)
        #expect(onPhone.session?.goalID == writing.id)
        #expect(onPhone.entries.filter { $0.goalID == reading.id }.map(\.amount) == [2000])
    }

    @Test("Three devices starting one after another count each stretch once")
    func threeDevices() {
        let goals = (1...3).map { index -> Goal in
            var goal = timeGoal(minutes: nil)
            goal.name = "Goal \(index)"
            return goal
        }
        let shared = AppData(goals: goals)
        var devices = [shared, shared, shared]
        for (index, device) in devices.indices.enumerated() {
            let start = Double(index) * 1000
            stamped(&devices[device], at: start) { $0.startFocus(on: goals[index].id, at: time(start), calendar: testCalendar) }
        }
        // Each device merges the other two at once, then settles.
        var settled: [AppData] = []
        for index in devices.indices {
            var merged = devices[index]
            for other in devices.indices where other != index { merged = SyncMerge.merge(merged, devices[other]) }
            merged.settleAfterMerge(from: devices[index], at: time(3000), calendar: testCalendar)
            settled.append(merged)
        }
        let everything = settled.dropFirst().reduce(settled[0]) { SyncMerge.merge($0, $1) }
        #expect(everything.session?.goalID == goals[2].id)
        #expect(everything.entries.filter { $0.goalID == goals[0].id }.map(\.amount) == [1000])
        #expect(everything.entries.filter { $0.goalID == goals[1].id }.map(\.amount) == [1000])
    }

    @Test("A goal encodes its weekdays in the same order every time")
    func weekdaysSorted() throws {
        let goal = checkInGoal(weekdays: [7, 2, 5, 3])
        let json = try #require(String(data: DateCoding.encoder().encode(goal), encoding: .utf8))
        #expect(json.contains("\"weekdays\":[2,3,5,7]"))
    }

    @Test("When a field is all that differs at the same moment, the copy that has it wins")
    func newerFieldWinsTie() throws {
        var goal = checkInGoal()
        var withChallenge = AppData(goals: [goal])
        stamped(&withChallenge, at: 5) { $0.startChallenge(on: goal.id, days: 30, from: DayID(year: 2026, month: 10, day: 1)) }
        // An older version reads the goal, drops the field it doesn't know, keeps the stamp.
        var older = withChallenge
        goal = try #require(older.goal(goal.id))
        goal.challenge = nil
        older.goals = [goal]
        #expect(SyncMerge.merge(withChallenge, older).goal(goal.id)?.challenge != nil)
        #expect(SyncMerge.merge(older, withChallenge).goal(goal.id)?.challenge != nil)
    }
}
