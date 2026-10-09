import AppIntents
import MomentumCore

/// A goal as Shortcuts, Siri and widget configuration see it.
struct GoalEntity: AppEntity, Equatable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Goal"
    static let defaultQuery = GoalQuery()

    let id: UUID
    let name: String
    let symbol: String
    let kind: GoalKind
    /// What it asks for, as "2h a day" or "12 books a year".
    let summary: String
    /// The category and notes, for search.
    let keywords: [String]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)", image: DisplayRepresentation.Image(systemName: symbol))
    }

    init(goal: Goal) {
        id = goal.id
        name = goal.name
        symbol = goal.symbol
        kind = goal.kind
        summary = goal.targetDescription
        keywords = [goal.category, kind.title].filter { !$0.isEmpty }
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
