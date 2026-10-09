import AppIntents
import Foundation
import MomentumCore

/// Starts a goal's focus timer at its default length, or stops it if it is the one running.
struct ToggleFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start or Stop Focus"
    static let isDiscoverable = false

    @Parameter(title: "Goal ID")
    var goalID: String

    init() {}

    init(goalID: UUID) {
        self.goalID = goalID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: goalID) {
            SharedStore.update { $0.toggleFocus(on: id) }
        }
        return .result()
    }
}

struct PauseResumeFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Focus"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        SharedStore.update { $0.togglePauseFocus() }
        return .result()
    }
}

/// The one-tap action: a check-in, the quick-add step, the next milestone, or pages read.
struct QuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Add"
    static let isDiscoverable = false

    @Parameter(title: "Goal ID")
    var goalID: String

    init() {}

    init(goalID: UUID) {
        self.goalID = goalID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: goalID) {
            SharedStore.update { $0.quickAdd(to: id) }
        }
        return .result()
    }
}
