import Foundation
import Testing
@testable import MomentumCore

@Suite("Goal colors")
struct GoalColorTests {
    @Test("A new goal takes the first color no active goal has, with purple and yellow last")
    func firstUnused() {
        let first = GoalColor.suggested(besides: [])
        let goals = [Goal(name: "Read", color: .blue, target: 1), Goal(name: "Run", color: .teal, target: 1)]
        let next = GoalColor.suggested(besides: goals)
        #expect(first == .blue)
        #expect(next == .green)
        let order = GoalColor.suggestionOrder
        let covered = Set(order) == Set(GoalColor.allCases) && order.count == GoalColor.allCases.count
        let purple = order.firstIndex(of: .purple) ?? 0
        let yellow = order.firstIndex(of: .yellow) ?? 0
        #expect(covered)
        #expect(purple >= order.count - 3)
        #expect(yellow >= order.count - 3)
    }

    @Test("Archived goals free their colors; with every color taken, the least used is picked")
    func archivedAndFull() {
        var archived = Goal(name: "Old", color: .blue, target: 1)
        archived.archivedAt = referenceNow
        let freed = GoalColor.suggested(besides: [archived])
        #expect(freed == .blue)
        var goals = GoalColor.allCases.map { Goal(name: $0.rawValue, color: $0, target: 1) }
        goals.append(Goal(name: "Another", color: .blue, target: 1))
        let leastUsed = GoalColor.suggested(besides: goals)
        #expect(leastUsed == .teal)
    }
}
