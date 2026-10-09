import Foundation
import Testing
@testable import MomentumCore

@Suite("Ring progress")
struct RingProgressTests {
    @Test("A ring keeps going past the target, up to two laps, while progress stops at one")
    func laps() {
        var data = AppData()
        let goal = timeGoal(target: 3600)
        data.upsert(goal)
        data.log(5400, for: goal.id, at: dayOffset(0, hour: 10))
        let halfwayRound = engine(data).ringProgress(for: goal, now: referenceNow)
        let capped = engine(data).progress(for: goal, now: referenceNow)
        #expect(abs(halfwayRound - 1.5) < 0.0001)
        #expect(capped == 1)

        data.log(36000, for: goal.id, at: dayOffset(0, hour: 11))
        let full = engine(data).ringProgress(for: goal, now: referenceNow)
        #expect(full == 2)
    }

    @Test("A goal with nothing to aim for draws an empty ring")
    func noTarget() {
        var data = AppData()
        let goal = Goal(name: "Plan", kind: .milestones, target: 0, createdAt: dayOffset(-3))
        data.upsert(goal)
        let ring = engine(data).ringProgress(for: goal, now: referenceNow)
        #expect(ring == 0)
    }
}
