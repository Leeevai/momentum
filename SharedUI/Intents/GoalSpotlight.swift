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
/// Updates run one after another, so a quick delete and undo can't land out of order.
@MainActor
enum GoalSpotlight {
    /// What was last sent to the index; nil until the first update of this launch.
    private static var indexed: [GoalEntity]?
    private static var pending: Task<Void, Never>?

    static func update(from data: AppData) {
        guard #available(iOS 18.0, macOS 15.0, *) else { return }
        let entities = data.goals.filter { !$0.isArchived }.map(GoalEntity.init)
        guard entities != indexed else { return }
        // The first update of a launch starts over: goals deleted on another device while the
        // app was closed aren't in `indexed` to be removed.
        let removed = indexed.map { Set($0.map(\.id)).subtracting(entities.map(\.id)) }
        indexed = entities
        let previous = pending
        pending = Task.detached(priority: .utility) {
            await previous?.value
            let index = CSSearchableIndex.default()
            do {
                if let removed {
                    if !removed.isEmpty {
                        try await index.deleteAppEntities(identifiedBy: Array(removed), ofType: GoalEntity.self)
                    }
                } else {
                    try await index.deleteAppEntities(ofType: GoalEntity.self)
                }
                try await index.indexAppEntities(entities)
            } catch {
                print("Spotlight indexing failed: \(error)")
            }
        }
    }
}
