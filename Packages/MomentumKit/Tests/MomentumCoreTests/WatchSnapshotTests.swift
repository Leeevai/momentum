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

    @Test("A break's goal goes out with the snapshot, however many goals come before it")
    func breakGoal() throws {
        let work = timeGoal()
        var data = AppData(goals: (0..<WatchSnapshot.itemLimit).map { _ in checkInGoal() } + [work])
        data.preferences.pomodoro.isEnabled = true
        data.startFocus(on: work.id, planned: 1500, at: referenceNow.addingTimeInterval(-1600), calendar: testCalendar)
        data.advancePomodoro(at: referenceNow, calendar: testCalendar)
        let rest = try #require(data.rest)
        #expect(data.session == nil)
        let snapshot = engine(data).watchSnapshot(now: referenceNow)
        let ids = snapshot.items.map(\.id)
        // The twelve goals ahead of it, and the break's goal first, as a running timer's would be.
        #expect(ids.count == WatchSnapshot.itemLimit + 1)
        #expect(ids.first == work.id)
        #expect(snapshot.rest == rest)
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
        let tomorrow = snapshot.current(at: dayOffset(1), calendar: testCalendar)
        #expect(tomorrow.done == 0)
        let item = try #require(tomorrow.item(gym.id))
        #expect(!item.isComplete)
        #expect(item.progress == 0)
        #expect(snapshot.current(at: referenceNow, calendar: testCalendar) == snapshot)
    }

    @Test("A weekly goal starts over at the week's end, not at midnight")
    func weeklyReset() throws {
        let gym = checkInGoal(period: .weekly, target: 1)
        var data = AppData(goals: [gym])
        data.log(1, for: gym.id, at: referenceNow)
        let snapshot = engine(data).watchSnapshot(now: referenceNow)
        // Thursday: tomorrow is still this week.
        #expect(snapshot.current(at: dayOffset(1), calendar: testCalendar).item(gym.id)?.isComplete == true)
        // Next Monday: a new week.
        let monday = try #require(snapshot.current(at: dayOffset(4), calendar: testCalendar).item(gym.id))
        #expect(!monday.isComplete)
    }

    @Test("A Start from the watch uses the goal's session length")
    func startUsesLength() {
        let work = timeGoal(minutes: 25)
        var data = AppData(goals: [work])
        data.apply(WatchCommand(action: .start(goal: work.id), date: referenceNow), now: referenceNow, calendar: testCalendar)
        #expect(data.session?.plannedDuration == 1500)
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

    @Test("The snapshot carries the iPhone's palette, custom ones too, as it looks in dark mode")
    func palette() throws {
        var data = AppData(goals: [timeGoal()])
        let custom = CustomPalette(name: "Tide", recipe: ThemePalette.fjord.recipe)
        data.preferences.choose(custom)
        let snapshot = engine(data).watchSnapshot(now: referenceNow)
        let palette = try #require(snapshot.palette)
        let expected = Palette(custom).dark.swatch(.green)
        let sent = palette.swatch(.green)
        #expect(abs(sent.lightness - expected.lightness) < 0.0001)
        #expect(abs(sent.chroma - expected.chroma) < 0.0001)
        #expect(abs(sent.hue - expected.hue) < 0.01)
        let decoded = try WatchSnapshot(encoded: snapshot.encoded())
        #expect(decoded == snapshot)
    }

    @Test("A snapshot without a palette decodes, and a damaged palette falls back without losing the snapshot")
    func paletteFallback() throws {
        var snapshot = engine(AppData(goals: [timeGoal()])).watchSnapshot(now: referenceNow)
        snapshot.palette = nil
        let older = try WatchSnapshot(encoded: snapshot.encoded())
        #expect(older.palette == nil)
        var object = try #require(try JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        let swatches: [Any] = [[0.5, 0.1, 200.0], "x"]
        let damagedPalette: [String: Any] = ["accent": "plaid", "swatches": swatches]
        object["palette"] = damagedPalette
        let damaged = try WatchSnapshot(encoded: JSONSerialization.data(withJSONObject: object))
        let palette = try #require(damaged.palette)
        let ids = damaged.items.map(\.id)
        #expect(ids == snapshot.items.map(\.id))
        #expect(palette == WatchPalette.standard)
    }

    @Test("Commands survive the trip as data, dates exact")
    func commandCoding() throws {
        let actions: [WatchAction] = [.start(goal: UUID()), .stop(goal: UUID(), sessionStart: referenceNow.addingTimeInterval(0.123)),
                                      .setPaused(goal: UUID(), sessionStart: referenceNow, paused: true), .quickAdd(goal: UUID()),
                                      .startNextBlock(restStart: referenceNow), .endRest(restStart: referenceNow)]
        for action in actions {
            let command = WatchCommand(action: action, date: referenceNow.addingTimeInterval(0.456))
            #expect(try WatchCommand(encoded: command.encoded()) == command)
        }
    }
}
