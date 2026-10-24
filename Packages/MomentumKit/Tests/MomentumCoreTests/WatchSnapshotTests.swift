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

    @Test("Goals not due today go out too, with their period")
    func others() throws {
        let gym = checkInGoal()
        // Weekends only, and the reference day is a Thursday.
        let hike = checkInGoal(weekdays: [1, 7])
        let data = AppData(goals: [gym, hike])
        let snapshot = engine(data).watchSnapshot(now: referenceNow)
        let todayIDs = snapshot.items.map(\.id)
        let otherIDs = snapshot.others?.map(\.id)
        let hikeItem = try #require(snapshot.item(hike.id))
        #expect(todayIDs == [gym.id])
        #expect(otherIDs == [hike.id])
        #expect(hikeItem.period == .daily)
    }

    @Test("The week counts daily goals met, time focused and active days")
    func week() throws {
        let gym = checkInGoal()
        let work = timeGoal()
        var data = AppData(goals: [work, gym])
        data.log(1, for: gym.id, at: dayOffset(-1))
        data.log(1, for: gym.id, at: dayOffset(0))
        data.log(1800, for: work.id, at: dayOffset(-2))
        data.log(3600, for: work.id, at: dayOffset(0))
        // The seven days before.
        data.log(600, for: work.id, at: dayOffset(-8))
        let week = try #require(engine(data).watchSnapshot(now: referenceNow).week)
        let due = week.days.map(\.due)
        let met = week.days.map(\.met)
        let focus = week.days.map(\.focus)
        let lastDay = week.days.last?.date
        let top = week.topGoals.map(\.id)
        #expect(due == [2, 2, 2, 2, 2, 2, 2])
        #expect(met == [0, 0, 0, 0, 0, 1, 2])
        #expect(focus == [0, 0, 0, 0, 1800, 0, 3600])
        #expect(lastDay == testCalendar.startOfDay(for: referenceNow))
        #expect(week.focus == 5400)
        #expect(week.previousFocus == 600)
        #expect(week.activeDays == 3)
        #expect(week.longestStreak == 2)
        #expect(top == [work.id])
    }

    @Test("A goal added on the watch is made once, in a color no other goal has")
    func addGoal() throws {
        let gym = checkInGoal()
        var data = AppData(goals: [gym])
        let new = WatchNewGoal(name: "  Stretch ", kind: .time, period: .daily, target: 600)
        let command = WatchCommand(action: .addGoal(goal: new), date: referenceNow)
        data.apply(command, now: time(60), calendar: testCalendar)
        data.apply(command, now: time(120), calendar: testCalendar)
        let added = try #require(data.goal(new.id))
        let count = data.goals.count
        #expect(count == 2)
        #expect(added.name == "Stretch")
        #expect(added.kind == .time)
        #expect(added.period == .daily)
        #expect(added.target == 600)
        #expect(added.color != gym.color)
        #expect(added.createdAt == referenceNow)
    }

    @Test("A template goal comes whole from the watch; a blank name or a goal deleted since makes nothing")
    func addGoalFromTemplate() throws {
        var data = AppData()
        let template = try #require(GoalTemplate.all.first { $0.id == "exercise" })
        let fromTemplate = WatchNewGoal(template: template)
        data.apply(WatchCommand(action: .addGoal(goal: fromTemplate), date: referenceNow), now: referenceNow)
        let made = try #require(data.goal(fromTemplate.id))
        #expect(made.unit == "workouts")
        #expect(made.period == .weekly)
        #expect(made.target == 4)

        let blank = WatchNewGoal(name: "  ", kind: .count, period: .daily, target: 3)
        data.apply(WatchCommand(action: .addGoal(goal: blank), date: referenceNow), now: referenceNow)
        #expect(data.goal(blank.id) == nil)

        // Deleted on another device since: a late copy of the command doesn't bring it back.
        data.goals.removeAll { $0.id == made.id }
        data.sync.tombstones[SyncState.goal(made.id)] = time(30)
        data.apply(WatchCommand(action: .addGoal(goal: fromTemplate), date: referenceNow), now: time(60))
        #expect(data.goal(made.id) == nil)
    }

    @Test("A snapshot from an iPhone without the other goals or the week decodes")
    func olderSnapshot() throws {
        let snapshot = engine(AppData(goals: [checkInGoal(), checkInGoal(weekdays: [1, 7])])).watchSnapshot(now: referenceNow)
        var object = try #require(try JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        object["others"] = nil
        object["week"] = nil
        let items = try #require(object["items"] as? [[String: Any]])
        object["items"] = items.map { item in
            var item = item
            item["period"] = nil
            return item
        }
        let older = try WatchSnapshot(encoded: JSONSerialization.data(withJSONObject: object))
        let ids = older.items.map(\.id)
        #expect(ids == snapshot.items.map(\.id))
        #expect(older.others == nil)
        #expect(older.week == nil)
        #expect(older.items.first?.period == nil)
    }

    @Test("Commands survive the trip as data, dates exact")
    func commandCoding() throws {
        let actions: [WatchAction] = [.start(goal: UUID()), .stop(goal: UUID(), sessionStart: referenceNow.addingTimeInterval(0.123)),
                                      .setPaused(goal: UUID(), sessionStart: referenceNow, paused: true), .quickAdd(goal: UUID()),
                                      .startNextBlock(restStart: referenceNow), .endRest(restStart: referenceNow),
                                      .addGoal(goal: WatchNewGoal(name: "Stretch", kind: .count, period: .weekly, target: 3))]
        for action in actions {
            let command = WatchCommand(action: action, date: referenceNow.addingTimeInterval(0.456))
            #expect(try WatchCommand(encoded: command.encoded()) == command)
        }
    }
}
