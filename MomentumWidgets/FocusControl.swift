import AppIntents
import MomentumCore
import SwiftUI
import WidgetKit

// Control Center and menu bar controls arrived on the Mac in macOS 26.
#if compiler(>=6.2)

/// A Control Center toggle: start focusing on the goal you timed most recently, or stop.
@available(macOS 26.0, *)
struct FocusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "FocusControl", provider: FocusControlProvider()) { state in
            ControlWidgetToggle(isOn: state.isRunning, action: SetFocusRunningIntent()) {
                Label(state.goalName ?? "Focus", systemImage: "timer")
            } valueLabel: { isOn in
                Label(isOn ? "Focusing" : "Start focus", systemImage: isOn ? "timer" : "play.fill")
            }
        }
        .displayName("Focus")
        .description("Start or stop a focus session on the goal you timed most recently.")
    }
}

@available(macOS 26.0, *)
struct FocusControlState {
    var isRunning: Bool
    var goalName: String?
}

@available(macOS 26.0, *)
struct FocusControlProvider: ControlValueProvider {
    var previewValue: FocusControlState { FocusControlState(isRunning: false, goalName: "Deep work") }

    func currentValue() async throws -> FocusControlState {
        let data = SharedStore.load()
        if let session = data.session {
            return FocusControlState(isRunning: true, goalName: data.goal(session.goalID)?.name)
        }
        return FocusControlState(isRunning: false, goalName: data.suggestedFocusGoal?.name)
    }
}

@available(macOS 26.0, *)
struct SetFocusRunningIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Focus"
    static let isDiscoverable = false

    @Parameter(title: "Focusing")
    var value: Bool

    func perform() async throws -> some IntentResult {
        SharedStore.update { data in
            if value {
                guard data.session == nil, let goal = data.suggestedFocusGoal else { return }
                let minutes = goal.focusMinutes ?? data.preferences.defaultFocusMinutes
                data.startFocus(on: goal.id, planned: Double(minutes) * 60)
            } else {
                data.stopFocus()
            }
        }
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}

#endif
