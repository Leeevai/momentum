import MomentumCore
import SwiftUI

/// The journal's two notifications, each a switch with its time: one in the morning to plan the
/// day, one in the evening to reflect on it. Rows for the notification settings on the Mac and
/// iPhone.
struct JournalReminderSettings: View {
    @Environment(GoalStore.self) private var store

    /// The times a reminder starts at when it's turned on.
    static let planDefault = 8 * 60
    static let reflectDefault = 21 * 60 + 30

    var body: some View {
        let preferences = store.data.preferences
        reminder("Plan the day", timeLabel: "Plan at", minute: preferences.planReminderMinute, startsAt: Self.planDefault,
                 \.planReminderMinute)
        reminder("Reflect on the day", timeLabel: "Reflect at", minute: preferences.reflectReminderMinute, startsAt: Self.reflectDefault,
                 \.reflectReminderMinute)
    }

    @ViewBuilder
    private func reminder(_ title: String, timeLabel: String, minute: Int?, startsAt: Int,
                          _ keyPath: WritableKeyPath<Preferences, Int?>) -> some View {
        Toggle(title, isOn: Binding(
            get: { minute != nil },
            set: { isOn in store.updatePreferences { $0[keyPath: keyPath] = isOn ? startsAt : nil } }
        ))
        if let minute {
            DatePicker(timeLabel, selection: Binding(
                get: { Self.time(minute) },
                set: { time in store.updatePreferences { $0[keyPath: keyPath] = Self.minute(of: time) } }
            ), displayedComponents: .hourAndMinute)
        }
    }

    /// Today at `minute` minutes after midnight, for the time picker.
    private static func time(_ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
    }

    private static func minute(of time: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
