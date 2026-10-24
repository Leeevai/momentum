import Foundation
import Testing
@testable import MomentumCore

@Suite("Combining goals")
struct CombineGoalsTests {
    @Test("The history moves to the goal kept, which keeps its settings, and the other goes")
    func movesHistory() throws {
        let kept = timeGoal(minutes: 25, target: 90_000)
        var copy = timeGoal(minutes: 50, target: 14_400)
        copy.milestones = [Milestone(title: "Chapter 1")]
        copy.links = [GoalLink(title: "Course", url: URL(string: "https://example.com/course")!)]
        var follower = checkInGoal()
        follower.stackAfter = copy.id
        var data = AppData(goals: [kept, copy, follower])
        data.log(3600, for: kept.id, at: dayOffset(-1))
        data.log(1800, for: copy.id, at: dayOffset(-1))
        data.log(600, for: copy.id, at: dayOffset(0))
        data.journal = [JournalEntry(day: DayID(dayOffset(0), calendar: testCalendar), priorities: [copy.id, kept.id])]

        data.combineGoal(copy.id, into: kept.id)

        let ids = data.goals.map(\.id)
        let owners = Set(data.entries.map(\.goalID))
        let count = data.entries.count
        let merged = try #require(data.goal(kept.id))
        let total = engine(data).lifetimeAmount(for: merged, now: referenceNow)
        let milestones = merged.milestones.map(\.title)
        let stacked = data.goal(follower.id)?.stackAfter
        let priorities = data.journal.first?.priorities
        #expect(ids == [kept.id, follower.id])
        #expect(owners == [kept.id])
        #expect(count == 3)
        #expect(total == 6000)
        #expect(merged.target == 90_000)
        #expect(merged.focusMinutes == 25)
        #expect(milestones == ["Chapter 1"])
        #expect(merged.links.count == 1)
        #expect(stacked == kept.id)
        #expect(priorities == [kept.id])
    }

    @Test("Only goals that count the same way combine, and not while the timer runs on the one going")
    func rules() {
        let work = timeGoal()
        let other = timeGoal()
        let gym = checkInGoal()
        let run = Goal(name: "Run", kind: .amount, unit: "km", target: 5)
        let walk = Goal(name: "Walk", kind: .amount, unit: " KM ", target: 3)
        let read = Goal(name: "Read", kind: .amount, unit: "pages", target: 20)
        var data = AppData(goals: [work, other, gym, run, walk, read])
        let timeWithTime = data.canCombine(work.id, into: other.id)
        let timeWithCount = data.canCombine(work.id, into: gym.id)
        let kmWithPages = data.canCombine(run.id, into: read.id)
        let kmWithKM = data.canCombine(walk.id, into: run.id)
        let itself = data.canCombine(work.id, into: work.id)
        let missing = data.canCombine(UUID(), into: work.id)
        #expect(timeWithTime)
        #expect(!timeWithCount)
        #expect(!kmWithPages)
        #expect(kmWithKM)
        #expect(!itself)
        #expect(!missing)

        data.session = FocusSession(goalID: work.id, plannedDuration: 1500, start: referenceNow)
        let whileRunning = data.canCombine(work.id, into: other.id)
        let intoRunning = data.canCombine(other.id, into: work.id)
        data.combineGoal(work.id, into: other.id)
        let stillThere = data.goal(work.id) != nil
        #expect(!whileRunning)
        #expect(intoRunning)
        #expect(stillThere)
    }

    @Test("A combination made on one device reaches another that still has both goals")
    func syncs() {
        let kept = timeGoal()
        let copy = timeGoal()
        var original = AppData(goals: [kept, copy])
        original.log(1800, for: kept.id, at: dayOffset(-1))
        original.log(900, for: copy.id, at: dayOffset(-1))
        let phone = original
        var combined = original
        combined.combineGoal(copy.id, into: kept.id)
        SyncStamper.stamp(&combined, from: original, at: referenceNow)
        for merged in [SyncMerge.merge(phone, combined), SyncMerge.merge(combined, phone)] {
            let ids = merged.goals.map(\.id)
            let owners = Set(merged.entries.map(\.goalID))
            let count = merged.entries.count
            #expect(ids == [kept.id])
            #expect(owners == [kept.id])
            #expect(count == 2)
        }
    }
}
