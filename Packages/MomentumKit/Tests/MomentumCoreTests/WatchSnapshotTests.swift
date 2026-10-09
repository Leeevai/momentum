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

    @Test("Actions from the watch change the data like the app would")
    func actions() {
        let gym = checkInGoal()
        let work = timeGoal()
        var data = AppData(goals: [work, gym])
        data.apply(.toggleFocus(goal: work.id), at: referenceNow, calendar: testCalendar)
        #expect(data.session?.goalID == work.id)
        data.apply(.togglePause, at: referenceNow.addingTimeInterval(600))
        #expect(data.session?.isRunning == false)
        data.apply(.stopFocus, at: referenceNow.addingTimeInterval(900), calendar: testCalendar)
        #expect(data.session == nil)
        #expect(data.entries.map(\.amount) == [600])
        // Starting a timer on a goal that isn't timed does nothing.
        data.apply(.toggleFocus(goal: gym.id), at: referenceNow)
        #expect(data.session == nil)
        data.apply(.quickAdd(goal: gym.id), at: referenceNow)
        #expect(data.entries.count == 2)
    }

    @Test("A snapshot of a full history stays small enough to send on every change")
    func size() throws {
        let data = AppData.demo()
        let snapshot = ProgressEngine(data: data).watchSnapshot(now: .now)
        let bytes = try DateCoding.encoder().encode(snapshot).count
        #expect(bytes < 16_000)
        let decoded = try DateCoding.decoder().decode(WatchSnapshot.self, from: DateCoding.encoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test("Actions survive the trip as data")
    func actionCoding() throws {
        let actions: [WatchAction] = [.toggleFocus(goal: UUID()), .togglePause, .stopFocus, .quickAdd(goal: UUID()), .startNextBlock, .endRest]
        for action in actions {
            let decoded = try JSONDecoder().decode(WatchAction.self, from: JSONEncoder().encode(action))
            #expect(decoded == action)
        }
    }
}
