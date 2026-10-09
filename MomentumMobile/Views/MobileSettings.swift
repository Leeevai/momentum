import MomentumCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings on iPhone: focus and Pomodoro, sync, journal and feedback.
struct MobileSettings: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picksFolder = false

    var body: some View {
        let preferences = store.data.preferences
        let pomodoro = preferences.pomodoro
        NavigationStack {
            Form {
                Section("Focus") {
                    Picker("Default session length", selection: binding(\.defaultFocusMinutes, preferences)) {
                        ForEach(FocusLengthMenu.lengths, id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    Picker("Focus sound", selection: binding(\.focusSound, preferences)) {
                        ForEach(FocusSound.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                    }
                    if preferences.focusSound != .off {
                        Slider(value: binding(\.focusSoundVolume, preferences), in: 0.05...1) { Text("Volume") }
                    }
                }
                Section {
                    Toggle("Chain sessions with breaks", isOn: pomodoroBinding(\.isEnabled, pomodoro))
                    if pomodoro.isEnabled {
                        Stepper("Short break: \(pomodoro.shortBreakMinutes) min", value: pomodoroBinding(\.shortBreakMinutes, pomodoro), in: 1...30)
                        Stepper("Long break: \(pomodoro.longBreakMinutes) min", value: pomodoroBinding(\.longBreakMinutes, pomodoro), in: 5...60, step: 5)
                        Stepper("Long break after \(pomodoro.blocksPerCycle) blocks", value: pomodoroBinding(\.blocksPerCycle, pomodoro), in: 2...8)
                        Toggle("Start the next block by itself", isOn: pomodoroBinding(\.autoStartsNextBlock, pomodoro))
                    }
                } header: {
                    Text("Pomodoro")
                } footer: {
                    Text("A planned session that reaches its length is saved and a break begins.")
                }
                if let sync = store.sync {
                    Section {
                        LabeledContent("Folder", value: sync.folder?.lastPathComponent ?? "Not syncing")
                        Button(sync.isEnabled ? "Change Folder" : "Choose a Folder in iCloud Drive") { picksFolder = true }
                        if sync.isEnabled {
                            Button("Sync Now") { sync.syncNow() }
                            ForEach(sync.peers) { peer in
                                LabeledContent {
                                    Text(peer.savedAt.formatted(.relative(presentation: .named)))
                                } label: {
                                    Label(peer.name, systemImage: peer.platform == "iOS" ? "iphone" : "laptopcomputer")
                                }
                            }
                            Button("Stop Syncing", role: .destructive) { sync.stop() }
                        }
                        if let error = sync.lastError {
                            Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Sync")
                    } footer: {
                        Text("Pick the same folder on your Mac and your iPhone. Each device keeps its own file there and merges the others'.")
                    }
                }
                Section("Coach and journal") {
                    Toggle("Plan the morning and reflect in the evening", isOn: binding(\.journalPromptsEnabled, preferences))
                    Toggle("Streak nudges in the evening", isOn: binding(\.streakNudgesEnabled, preferences))
                    Toggle("Weekly recap", isOn: binding(\.weeklyRecapEnabled, preferences))
                    Toggle("Goal reminders", isOn: binding(\.remindersEnabled, preferences))
                }
                Section("Feedback") {
                    Toggle("Celebrate finished goals", isOn: binding(\.celebratesCompletion, preferences))
                    Toggle("Haptics", isOn: binding(\.playsSounds, preferences))
                }
                Section {
                    Link(destination: URL(string: "https://github.com/Leeevai/momentum")!) {
                        Label("Momentum on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } footer: {
                    Text("Momentum keeps everything on your devices. No accounts, no tracking.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $picksFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { store.sync?.useFolder(url) }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>, _ preferences: Preferences) -> Binding<Value> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } })
    }

    private func pomodoroBinding<Value>(_ keyPath: WritableKeyPath<PomodoroSettings, Value>, _ settings: PomodoroSettings) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in store.updatePreferences { $0.pomodoro[keyPath: keyPath] = value } })
    }
}
