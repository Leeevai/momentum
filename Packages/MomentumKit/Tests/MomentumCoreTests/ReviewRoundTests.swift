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
        let changed = merged.settleAfterMerge(keeping: phone.session, calendar: testCalendar)
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
        let changed = merged.settleAfterMerge(keeping: phone.session, calendar: testCalendar)
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
        merged.settleAfterMerge(keeping: phone.session, calendar: testCalendar)
        #expect(merged.session?.goalID == writing.id)
        #expect(merged.entries.filter { $0.goalID == reading.id }.map(\.amount) == [1800])
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
