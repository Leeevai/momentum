import Foundation
import Testing
@testable import MomentumCore

@Suite("Watch snapshot")
struct WatchSnapshotTests {
    @Test("Today's goals go out with their progress and one-tap actions")
    func items() throws {
        let gym = checkInGoal()
        let work = timeGoal()
        var data = AppData(goals: [work, gym])
        data.log(1, for: gym.id, at: referenceNow)
        let snapshot = engine(data).watchSnapshot(now: referenceNow)
        #expect(snapshot.items.map(\.id) == [work.id, gym.id])
        let gymItem = try #require(snapshot.item(gym.id))
        #expect(gymItem.isComplete)
        #expect(gymItem.actionTitle == "+1")
        #expect(snapshot.item(work.id)?.actionTitle == nil)
        #expect(snapshot.done == 1)
        #expect(snapshot.total == 2)
    }

    @Test("Commands from the watch change the data like the app would, dated when tapped")
    func commands() throws {
        let gym = checkInGoal()
        let work = timeGoal()
        var data = AppData(goals: [work, gym])
        data.apply(WatchCommand(action: .start(goal: work.id), date: referenceNow), now: referenceNow, calendar: testCalendar)
        let session = try #require(data.session)
        #expect(session.goalID == work.id)
        let start = session.startedAt
        data.apply(WatchCommand(action: .setPaused(goal: work.id, sessionStart: start, paused: true), date: time(600)), now: time(600))
        #expect(data.session?.isRunning == false)
        // Tapped at 15 minutes, delivered hours later: only the time before the tap counts.
        data.apply(WatchCommand(action: .stop(goal: work.id, sessionStart: start), date: time(900)), now: time(4 * 3600), calendar: testCalendar)
        #expect(data.session == nil)
        #expect(data.entries.map(\.amount) == [600])
        // Starting a timer on a goal that isn't timed does nothing.
        data.apply(WatchCommand(action: .start(goal: gym.id), date: time(5000)), now: time(5000))
        #expect(data.session == nil)
        data.apply(WatchCommand(action: .quickAdd(goal: gym.id), date: time(5000)), now: time(5000))
        #expect(data.entries.count == 2)
    }

    @Test("A late or repeated command can't undo what it was for")
    func idempotent() throws {
        let work = timeGoal()
        var data = AppData(goals: [work])
        let startCommand = WatchCommand(action: .start(goal: work.id), date: referenceNow)
        data.apply(startCommand, now: referenceNow, calendar: testCalendar)
        let start = try #require(data.session?.startedAt)
        // The same Start again (its reply was lost) leaves the session running.
        data.apply(startCommand, now: time(60), calendar: testCalendar)
        #expect(data.session?.startedAt == start)
        let stop = WatchCommand(action: .stop(goal: work.id, sessionStart: start), date: time(1200))
        data.apply(stop, now: time(1200), calendar: testCalendar)
        data.apply(stop, now: time(1300), calendar: testCalendar)
        #expect(data.session == nil)
        #expect(data.entries.count == 1)
        // A Stop for a session that ended doesn't touch a newer one.
        data.apply(WatchCommand(action: .start(goal: work.id), date: time(2000)), now: time(2000), calendar: testCalendar)
        data.apply(stop, now: time(2100), calendar: testCalendar)
        #expect(data.session != nil)
    }

    @Test("A snapshot from yesterday shows daily goals starting over")
    func staleDay() throws {
        let gym = checkInGoal()
        var data = AppData(goals: [gym])
        data.log(1, for: gym.id, at: referenceNow)
        let snapshot = engine(data).watchSnapshot(now: referenceNow)
        #expect(snapshot.done == 1)
        let tomorrow = snapshot.current(on: DayID(dayOffset(1), calendar: testCalendar))
        #expect(tomorrow.done == 0)
        let item = try #require(tomorrow.item(gym.id))
        #expect(!item.isComplete)
        #expect(item.progress == 0)
        #expect(snapshot.current(on: snapshot.day) == snapshot)
    }

    private func time(_ seconds: Double) -> Date { referenceNow.addingTimeInterval(seconds) }

    @Test("A snapshot of a full history stays small enough to send on every change")
    func size() throws {
        let data = AppData.demo()
        let snapshot = ProgressEngine(data: data).watchSnapshot(now: .now)
        let bytes = try DateCoding.encoder().encode(snapshot).count
        #expect(bytes < 16_000)
        let decoded = try DateCoding.decoder().decode(WatchSnapshot.self, from: DateCoding.encoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test("Commands survive the trip as data, dates exact")
    func commandCoding() throws {
        let actions: [WatchAction] = [.start(goal: UUID()), .stop(goal: UUID(), sessionStart: referenceNow.addingTimeInterval(0.123)),
                                      .setPaused(goal: UUID(), sessionStart: referenceNow, paused: true), .quickAdd(goal: UUID()),
                                      .startNextBlock, .endRest]
        for action in actions {
            let command = WatchCommand(action: action, date: referenceNow.addingTimeInterval(0.456))
            #expect(try WatchCommand(encoded: command.encoded()) == command)
        }
    }
}
