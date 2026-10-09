import Foundation
import Testing
@testable import MomentumCore

@Suite("Coach")
struct CoachTests {
    @Test("An unkept streak gets an urgent tip in the evening, not at lunch")
    func streakAtRisk() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        for offset in -5...(-1) { data.log(1, for: goal.id, at: dayOffset(offset)) }
        let evening = dayOffset(0, hour: 19)
        let tips = engine(data).coachTips(now: evening)
        #expect(tips.first?.id == "risk-\(goal.id)")
        #expect(tips.first?.tone == .urgent)
        #expect(tips.first?.title == "Keep your 5-day Gym streak")
        #expect(!engine(data).coachTips(now: dayOffset(0, hour: 12)).contains { $0.id.hasPrefix("risk") })
    }

    @Test("Finishing an anchor suggests the goal stacked after it")
    func nextInStack() {
        let coffee = checkInGoal()
        var read = checkInGoal()
        read.name = "Read"
        read.stackAfter = coffee.id
        var data = AppData(goals: [coffee, read])
        data.log(1, for: coffee.id, at: referenceNow)
        let tip = engine(data).coachTips(now: referenceNow).first { $0.id == "stack-\(read.id)" }
        #expect(tip?.title == "Next up: Read")
        #expect(tip?.action == .log(read.id))
    }

    @Test("Three weeks of easy wins suggests a bigger target; three weeks of misses a smaller one")
    func targets() {
        let goal = timeGoal(target: 1800)
        var data = AppData(goals: [goal])
        for offset in -21...(-1) { data.log(1800, for: goal.id, at: dayOffset(offset)) }
        let raise = engine(data).coachTips(now: referenceNow, limit: 10).first { $0.id == "raise-\(goal.id)" }
        #expect(raise?.action == .setTarget(goal.id, 2700.0))

        let struggling = timeGoal(target: 3600, createdDaysAgo: 40)
        let lowered = AppData(goals: [struggling])
        let lower = engine(lowered).coachTips(now: referenceNow, limit: 10).first { $0.id == "lower-\(struggling.id)" }
        #expect(lower?.action == .setTarget(struggling.id, 2100.0))
    }

    @Test("Mornings invite a plan and evenings a reflection, until written")
    func journalPrompts() {
        let goal = checkInGoal()
        var data = AppData(goals: [goal])
        #expect(engine(data).coachTips(now: dayOffset(0, hour: 8), limit: 10).contains { $0.action == .planDay })
        data.updateJournal(for: DayID(referenceNow, calendar: testCalendar)) { $0.intention = "Train" }
        #expect(!engine(data).coachTips(now: dayOffset(0, hour: 8), limit: 10).contains { $0.action == .planDay })
        #expect(engine(data).coachTips(now: dayOffset(0, hour: 21), limit: 10).contains { $0.action == .reflect })
    }

    @Test("Suggested targets step in round amounts")
    func suggestedTargets() {
        #expect(timeGoal(target: 1200).suggestedTarget(raising: true) == 1500.0)
        #expect(timeGoal(target: 7200).suggestedTarget(raising: true) == 8100.0)
        #expect(timeGoal(target: 10800).suggestedTarget(raising: true) == 12600.0)
        #expect(timeGoal(target: 600).suggestedTarget(raising: false) == 300.0)
        #expect(checkInGoal(target: 4).suggestedTarget(raising: true) == 5.0)
        #expect(checkInGoal(target: 1).suggestedTarget(raising: false) == 1.0)
        let pages = Goal(name: "Pages", kind: .amount, unit: "pages", target: 20, quickAddStep: 5)
        #expect(pages.suggestedTarget(raising: true) == 25.0)
        #expect(pages.suggestedTarget(raising: false) == 10.0)
    }
}
