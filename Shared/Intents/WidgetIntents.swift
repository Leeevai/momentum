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
            let data = SharedStore.update { $0.toggleFocus(on: id) }
            await LiveActivitySync.after(data)
        }
        return .result()
    }
}

struct PauseResumeFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Focus"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let data = SharedStore.update { $0.togglePauseFocus() }
        await LiveActivitySync.after(data)
        return .result()
    }
}

/// Ends a Pomodoro break and starts the next block.
struct StartNextBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Next Block"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let data = SharedStore.update { $0.startNextBlock() }
        await LiveActivitySync.after(data)
        return .result()
    }
}

/// Ends a Pomodoro break without starting anything.
struct EndBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Break"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let data = SharedStore.update { $0.endRest() }
        await LiveActivitySync.after(data)
        return .result()
    }
}

/// Keeps the Lock Screen timer in step after an intent changes the data. On iPhone the timer
/// intents are Live Activity intents, so they run in the app, which may update the activity.
enum LiveActivitySync {
    static func after(_ data: AppData) async {
        #if os(iOS)
        await FocusActivityController.sync(with: data)
        #endif
    }
}

#if os(iOS)
extension ToggleFocusIntent: LiveActivityIntent {}
extension PauseResumeFocusIntent: LiveActivityIntent {}
extension StartNextBlockIntent: LiveActivityIntent {}
extension EndBreakIntent: LiveActivityIntent {}
#endif

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
