import AppIntents
import MomentumCore

/// A Focus filter: in System Settings → Focus, choose which goal categories Momentum shows while
/// that Focus is on. The system runs this when the Focus starts, and again with no categories
/// when it ends.
struct MomentumFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Show Goals"
    static let description: IntentDescription? = IntentDescription("Show only the goals in these categories while this Focus is on.")

    @Parameter(title: "Categories", optionsProvider: CategoryOptions())
    var categories: [String]?

    var displayRepresentation: DisplayRepresentation {
        let chosen = categories ?? []
        return DisplayRepresentation(title: "Momentum", subtitle: chosen.isEmpty ? "All goals" : "\(chosen.formatted(.list(type: .and)))")
    }

    func perform() async throws -> some IntentResult {
        let chosen = Set(categories ?? [])
        SharedStore.saveFocusFilter(chosen.isEmpty ? nil : FocusFilter(categories: chosen))
        return .result()
    }
}

struct CategoryOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        SharedStore.load().categoryNames
    }
}
