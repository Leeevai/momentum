import AppIntents
import CoreSpotlight
import MomentumCore

/// Opens a goal in the app: what Spotlight runs when a goal is picked from its results, and an
/// "Open Goal" action in Shortcuts.
struct OpenGoalIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Goal"
    static let description = IntentDescription("Opens a goal in Momentum.")

    @Parameter(title: "Goal")
    var target: GoalEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        LinkRouter.open(.goal(target.id))
        return .result()
    }
}

@available(iOS 18.0, macOS 15.0, *)
extension GoalEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.displayName = name
        attributes.contentDescription = summary
        attributes.keywords = keywords
        return attributes
    }
}

/// Keeps the goals in Spotlight: re-indexed when one is added, renamed, archived or deleted.
@MainActor
enum GoalSpotlight {
    private static var indexed: [GoalEntity] = []

    static func update(from data: AppData) {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let entities = data.goals.filter { !$0.isArchived }.map(GoalEntity.init)
        guard entities != indexed else { return }
        let removed = Set(indexed.map(\.id)).subtracting(entities.map(\.id))
        indexed = entities
        Task.detached(priority: .utility) {
            let index = CSSearchableIndex.default()
            do {
                if !removed.isEmpty {
                    try await index.deleteAppEntities(identifiedBy: Array(removed), ofType: GoalEntity.self)
                }
                try await index.indexAppEntities(entities)
            } catch {
                print("Spotlight indexing failed: \(error)")
            }
        }
    }
}
