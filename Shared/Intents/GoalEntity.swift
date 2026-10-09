import AppIntents
import MomentumCore

/// A goal as Shortcuts, Siri and widget configuration see it.
struct GoalEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Goal"
    static let defaultQuery = GoalQuery()

    let id: UUID
    let name: String
    let icon: String
    let kind: GoalKind

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(icon) \(name)", subtitle: "\(kind.title)")
    }

    init(goal: Goal) {
        id = goal.id
        name = goal.name
        icon = goal.icon
        kind = goal.kind
    }
}

struct GoalQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [GoalEntity] {
        SharedStore.load().goals
            .filter { identifiers.contains($0.id) }
            .map(GoalEntity.init)
    }

    func entities(matching string: String) async throws -> [GoalEntity] {
        SharedStore.load().goals
            .filter { !$0.isArchived && $0.name.localizedCaseInsensitiveContains(string) }
            .map(GoalEntity.init)
    }

    func suggestedEntities() async throws -> [GoalEntity] {
        SharedStore.load().goals.filter { !$0.isArchived }.map(GoalEntity.init)
    }

    func defaultResult() async -> GoalEntity? {
        SharedStore.load().goals.first { !$0.isArchived }.map(GoalEntity.init)
    }
}
