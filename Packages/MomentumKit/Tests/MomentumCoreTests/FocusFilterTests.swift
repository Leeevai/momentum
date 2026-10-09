import Foundation
import Testing
@testable import MomentumCore

@Suite("Focus filters")
struct FocusFilterTests {
    let work = Goal(name: "Deep work", category: "Work", target: 1)
    let gym = Goal(name: "Gym", category: "Fitness", target: 1)
    let loose = Goal(name: "Loose", target: 1)

    @Test("A filter shows its categories, and uncategorized goals by \"Goals\"")
    func filters() {
        let filter = FocusFilter(categories: ["Work", "Goals"])
        #expect(filter.apply(to: [work, gym, loose], session: nil).map(\.name) == ["Deep work", "Loose"])
        #expect(FocusFilter(categories: []).apply(to: [work, gym], session: nil).count == 2)
    }

    @Test("A running timer's goal stays visible")
    func keepsRunningGoal() {
        let filter = FocusFilter(categories: ["Work"])
        let session = FocusSession(goalID: gym.id, start: referenceNow)
        #expect(filter.apply(to: [work, gym], session: session).map(\.name) == ["Deep work", "Gym"])
    }

    @Test("Category names come in goal order, without duplicates or archived goals")
    func categoryNames() {
        var archived = Goal(name: "Old", category: "Finance", target: 1)
        archived.archivedAt = referenceNow
        let data = AppData(goals: [work, loose, gym, Goal(name: "More work", category: "Work", target: 1), archived])
        #expect(data.categoryNames == ["Work", "Goals", "Fitness"])
    }
}
