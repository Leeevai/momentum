#if os(iOS)
import ActivityKit
import Foundation
import MomentumCore
import OSLog

/// The focus timer on the Lock Screen and in the Dynamic Island.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case focusing, paused, resting
        }

        var phase: Phase
        /// Where an elapsed counter starts, had it never paused (counting up).
        var counterStart: Date
        /// The planned end of the block or break, counted down to; nil counts up.
        var end: Date?
        /// Time focused so far, shown while paused.
        var elapsed: TimeInterval
        /// The Pomodoro block number, when cycles are on.
        var block: Int?
    }

    var goalID: String
    var goalName: String
    var symbol: String
    var color: String
}

/// Starts, updates and ends the focus Live Activity to match the data, from the app or from an
/// intent run on the Lock Screen.
enum FocusActivityController {
    private static let logger = Logger(subsystem: "dev.momentum.shared", category: "LiveActivity")

    static func sync(with data: AppData, now: Date = .now) async {
        guard let (attributes, state) = content(for: data, now: now) else {
            for activity in Activity<FocusActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        let content = ActivityContent(state: state, staleDate: state.end.map { $0.addingTimeInterval(60) })
        var updated = false
        for activity in Activity<FocusActivityAttributes>.activities {
            if activity.attributes.goalID == attributes.goalID && !updated {
                await activity.update(content)
                updated = true
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard !updated, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: attributes, content: content)
        } catch {
            // Only a foreground app may start one; the next sync from the app will.
            logger.error("Could not start the Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// What the activity should show for `data`, or nil when nothing is running.
    static func content(for data: AppData, now: Date) -> (FocusActivityAttributes, FocusActivityAttributes.ContentState)? {
        let pomodoro = data.preferences.pomodoro.isEnabled
        if let session = data.session, let goal = data.goal(session.goalID) {
            let elapsed = session.elapsed(at: now)
            let state = FocusActivityAttributes.ContentState(
                phase: session.isRunning ? .focusing : .paused,
                counterStart: session.counterReferenceDate ?? now.addingTimeInterval(-elapsed),
                end: session.plannedEnd,
                elapsed: elapsed,
                block: pomodoro ? session.block : nil)
            return (attributes(for: goal), state)
        }
        if let rest = data.rest, !rest.isOver(at: now), let goal = data.goal(rest.goalID) {
            let state = FocusActivityAttributes.ContentState(phase: .resting, counterStart: rest.start, end: rest.end, elapsed: 0,
                                                             block: rest.nextBlock)
            return (attributes(for: goal), state)
        }
        return nil
    }

    private static func attributes(for goal: Goal) -> FocusActivityAttributes {
        FocusActivityAttributes(goalID: goal.id.uuidString, goalName: goal.name, symbol: goal.symbol, color: goal.color.rawValue)
    }
}
#endif
