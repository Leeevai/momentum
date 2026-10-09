import MomentumCore
import SwiftUI

/// Something the user just did, for a haptic that matches it.
///
/// It comes from comparing the data before and after a change of the user's own, so every way of
/// doing a thing (a button, a swipe, a menu, a keyboard shortcut) feels the same, and changes from
/// a widget or another device stay quiet.
struct HapticEvent: Equatable {
    enum Kind: Equatable {
        case started, stopped, paused, resumed, onBreak, increased, decreased, adjusted
    }

    let id = UUID()
    let kind: Kind

    init?(from before: AppData, to after: AppData) {
        guard let kind = Self.kind(from: before, to: after) else { return nil }
        self.kind = kind
    }

    private static func kind(from before: AppData, to after: AppData) -> Kind? {
        switch (before.session, after.session) {
        case (nil, .some):
            return .started
        case (.some, nil):
            return before.rest == nil && after.rest != nil ? .onBreak : .stopped
        case let (old?, new?):
            if !old.isSameSession(as: new) { return .started }
            if old.isRunning != new.isRunning { return new.isRunning ? .resumed : .paused }
        case (nil, nil):
            break
        }
        if before.entries.count != after.entries.count {
            return after.entries.count > before.entries.count ? .increased : .decreased
        }
        let doneBefore = milestonesDone(in: before)
        let doneAfter = milestonesDone(in: after)
        if doneBefore != doneAfter { return doneAfter > doneBefore ? .increased : .decreased }
        if before.entries != after.entries { return .adjusted }
        return nil
    }

    private static func milestonesDone(in data: AppData) -> Int {
        data.goals.reduce(0) { total, goal in total + goal.milestones.count(where: \.isDone) }
    }

    var feedback: SensoryFeedback {
        switch kind {
        case .started: .start
        case .stopped: .stop
        case .paused, .resumed: .impact(weight: .light)
        case .onBreak: .impact(flexibility: .soft)
        case .increased: .increase
        case .decreased: .decrease
        case .adjusted: .selection
        }
    }
}

extension View {
    /// Haptics for the user's changes, for reaching a goal, and for earning an award, unless
    /// they're turned off in Settings.
    func appHaptics(_ store: GoalStore) -> some View {
        let enabled = store.data.preferences.playsSounds
        return self
            .sensoryFeedback(trigger: store.haptic) { _, event in enabled ? event?.feedback : nil }
            .sensoryFeedback(trigger: store.celebration?.id) { _, id in enabled && id != nil ? .success : nil }
            .sensoryFeedback(trigger: store.toast?.id) { _, _ in
                guard enabled else { return nil }
                switch store.toast?.kind {
                case .achievement, .achievements: return .success
                case .message, nil: return nil
                }
            }
    }
}
