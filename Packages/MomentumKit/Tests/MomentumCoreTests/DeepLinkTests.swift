import Foundation
import Testing
@testable import MomentumCore

@Suite("Deep links")
struct DeepLinkTests {
    @Test("Every link round-trips through its URL", arguments: [
        DeepLink.today,
        .insights,
        .newGoal,
        .goal(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!),
        .openLink(goal: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, link: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!),
    ])
    func roundTrip(link: DeepLink) {
        #expect(DeepLink(url: link.url) == link)
        #expect(link.url.scheme == "momentum")
    }

    @Test("Foreign and malformed URLs are rejected")
    func rejects() {
        #expect(DeepLink(url: URL(string: "https://example.com/goal/x")!) == nil)
        #expect(DeepLink(url: URL(string: "momentum://goal/not-a-uuid")!) == nil)
        #expect(DeepLink(url: URL(string: "momentum://somewhere")!) == nil)
    }
}

@Suite("Insights comparison")
struct InsightsComparisonTests {
    @Test("Focus is compared with the equally long range before")
    func weekOverWeek() throws {
        let goal = Goal(name: "Focus", kind: .time, target: 3600, createdAt: date(2026, 9, 1))
        var data = AppData(goals: [goal])
        data.log(3600, for: goal.id, at: dayOffset(-2))   // this week
        data.log(1800, for: goal.id, at: dayOffset(-9))   // the week before
        data.log(1800, for: goal.id, at: dayOffset(-10))
        let report = engine(data).insights(days: 7, now: referenceNow)
        #expect(report.totalFocusSeconds == 3600)
        #expect(report.previousFocusSeconds == 3600)
        #expect(report.previousActiveDays == 2)
        #expect(try #require(report.focusChange) == 0)
    }

    @Test("Focus is grouped by category, largest first")
    func byCategory() {
        let work = Goal(name: "Work", category: "Work", kind: .time, target: 3600, createdAt: date(2026, 9, 1))
        let study = Goal(name: "Study", category: "Learning", kind: .time, target: 3600, createdAt: date(2026, 9, 1))
        let loose = Goal(name: "Loose", kind: .time, target: 3600, createdAt: date(2026, 9, 1))
        var data = AppData(goals: [work, study, loose])
        data.log(3600, for: work.id, at: dayOffset(-1))
        data.log(1800, for: study.id, at: dayOffset(-1))
        data.log(600, for: loose.id, at: dayOffset(-1))
        let shares = engine(data).insights(days: 7, now: referenceNow).focusByCategory
        #expect(shares.map(\.name) == ["Work", "Learning", "Other"])
        #expect(shares.map(\.seconds) == [3600, 1800, 600])
    }
}
