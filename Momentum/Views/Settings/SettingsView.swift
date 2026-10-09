import AppKit
import MomentumCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            FocusSettings()
                .tabItem { Label("Focus", systemImage: "timer") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            SyncSettings()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath.icloud") }
            DataSettings()
                .tabItem { Label("Data", systemImage: "externaldrive") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500)
    }
}

private struct GeneralSettings: View {
    @Environment(GoalStore.self) private var store
    @State private var opensAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        let preferences = store.data.preferences
        Form {
            Section {
                Toggle("Open at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { _, enabled in
                        do {
                            try LoginItem.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            opensAtLogin = LoginItem.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Show the focus timer in the menu bar", isOn: binding(\.showsTimerInMenuBar, preferences))
            }
            Section {
                LabeledContent("Quick actions from anywhere") {
                    HotKeyRecorder()
                }
                Text("Opens a floating panel over any app: type a goal and press Return to start or log it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Coach and journal") {
                Toggle("Invite me to plan the morning and reflect in the evening", isOn: binding(\.journalPromptsEnabled, preferences))
            }
            Section("Feedback") {
                Toggle("Celebrate finished goals with confetti", isOn: binding(\.celebratesCompletion, preferences))
                Toggle("Play sounds", isOn: binding(\.playsSounds, preferences))
            }
        }
        .formStyle(.grouped)
        .frame(height: 460)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>, _ preferences: Preferences) -> Binding<Value> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } })
    }
}

private struct FocusSettings: View {
    @Environment(GoalStore.self) private var store
    @State private var volume: Double?

    var body: some View {
        let preferences = store.data.preferences
        let pomodoro = preferences.pomodoro
        Form {
            Section {
                Picker("Default session length", selection: binding(\.defaultFocusMinutes, preferences)) {
                    ForEach(FocusLengthMenu.lengths, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Text("Used by Shortcuts, Siri and Pomodoro blocks when a goal has no length of its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Ask how each session went", isOn: binding(\.asksSessionQuality, preferences))
                Text("One tap after a session of five minutes or more: scattered, steady or in the flow. Insights shows when your sessions go best.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Pomodoro") {
                Toggle("Chain sessions with breaks", isOn: pomodoroBinding(\.isEnabled, pomodoro))
                Group {
                    Stepper("Short break: \(pomodoro.shortBreakMinutes) min", value: pomodoroBinding(\.shortBreakMinutes, pomodoro), in: 1...30)
                    Stepper("Long break: \(pomodoro.longBreakMinutes) min", value: pomodoroBinding(\.longBreakMinutes, pomodoro), in: 5...60, step: 5)
                    Stepper("Long break after \(pomodoro.blocksPerCycle) blocks", value: pomodoroBinding(\.blocksPerCycle, pomodoro), in: 2...8)
                    Toggle("Start the next block when a break ends", isOn: pomodoroBinding(\.autoStartsNextBlock, pomodoro))
                }
                .disabled(!pomodoro.isEnabled)
                Text("When a planned session reaches its length, it is saved and a break begins. Finish a whole cycle to earn Full Cycle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sound") {
                Picker("Focus sound", selection: binding(\.focusSound, preferences)) {
                    ForEach(FocusSound.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                // Saved when the slider is let go, not on every step of the drag.
                Slider(value: Binding(get: { volume ?? preferences.focusSoundVolume }, set: { volume = $0 }), in: 0.05...1) {
                    Text("Volume")
                } onEditingChanged: { editing in
                    guard !editing, let volume else { return }
                    store.updatePreferences { $0.focusSoundVolume = volume }
                    self.volume = nil
                }
                .disabled(preferences.focusSound == .off)
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>, _ preferences: Preferences) -> Binding<Value> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } })
    }

    private func pomodoroBinding<Value>(_ keyPath: WritableKeyPath<PomodoroSettings, Value>, _ settings: PomodoroSettings) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in store.updatePreferences { $0.pomodoro[keyPath: keyPath] = value } })
    }
}

private struct SyncSettings: View {
    @Environment(GoalStore.self) private var store

    var body: some View {
        Form {
            if let sync = store.sync {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: sync.isEnabled ? "checkmark.icloud.fill" : "icloud.slash")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(sync.isEnabled ? Color.accentColor : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sync.isEnabled ? "Syncing" : "Not syncing")
                                .font(.headline)
                            if let folder = sync.folder {
                                Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Pick a folder in iCloud Drive, or any folder your devices share.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    HStack {
                        Button(sync.isEnabled ? "Change Folder…" : "Choose Folder…") { sync.chooseFolder() }
                        if sync.isEnabled {
                            Button("Sync Now") { sync.syncNow() }
                            Spacer()
                            Button("Stop Syncing", role: .destructive) { sync.stop() }
                        }
                    }
                    if let error = sync.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let last = sync.lastSync {
                        Text("Last synced \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if sync.isEnabled {
                    Section("Other devices") {
                        if sync.peers.isEmpty {
                            Text("None yet. Choose the same folder on your other devices.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(sync.peers) { peer in
                            HStack {
                                Label(peer.name, systemImage: peer.platform == "iOS" ? "iphone" : "laptopcomputer")
                                Spacer()
                                Text(peer.savedAt.formatted(.relative(presentation: .named)))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("Each device keeps its own file in the folder and merges the others' into its data: the latest change to each goal wins, and progress logged anywhere adds up. Nothing leaves your devices and the folder's service.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 460)
    }
}

private struct NotificationSettings: View {
    @Environment(GoalStore.self) private var store

    var body: some View {
        let scheduler = store.effects.notifications
        let enabled = store.data.preferences.remindersEnabled
        Form {
            Section {
                Toggle("Goal reminders", isOn: Binding(get: { enabled }, set: { value in store.updatePreferences { $0.remindersEnabled = value } }))
                Text("Each goal can remind you at its own time. Reminders skip days the goal is already done, unscheduled days, and breaks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Streak protection") {
                Toggle("Nudge me when a streak would end at midnight", isOn: Binding(
                    get: { store.data.preferences.streakNudgesEnabled },
                    set: { value in store.updatePreferences { $0.streakNudgesEnabled = value } }
                ))
                DatePicker("Nudge at", selection: Binding(
                    get: {
                        let minute = store.data.preferences.streakNudgeMinute
                        return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
                    },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        store.updatePreferences { $0.streakNudgeMinute = (parts.hour ?? 20) * 60 + (parts.minute ?? 0) }
                    }
                ), displayedComponents: .hourAndMinute)
                .disabled(!store.data.preferences.streakNudgesEnabled)
                Text("Only for goals with a streak of two or more, on the last day of their period, if they're not done yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Weekly recap on the last evening of the week", isOn: Binding(
                    get: { store.data.preferences.weeklyRecapEnabled },
                    set: { value in store.updatePreferences { $0.weeklyRecapEnabled = value } }
                ))
            }
            Section("Permission") {
                LabeledContent("Status") {
                    Text(scheduler.authorization.text)
                        .foregroundStyle(scheduler.authorization == .denied ? .red : .secondary)
                }
                if scheduler.authorization == .notDetermined {
                    Button("Allow Notifications") {
                        Task { await scheduler.requestAuthorization() }
                    }
                } else if scheduler.authorization == .denied {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            Section("Goals with reminders") {
                let reminded = store.engine.activeGoals.filter { $0.reminder?.isEnabled == true }
                if reminded.isEmpty {
                    Text("None yet. Turn one on in a goal's editor.")
                        .foregroundStyle(.secondary)
                }
                ForEach(reminded) { goal in
                    LabeledContent {
                        if let reminder = goal.reminder {
                            Text(String(format: "%02d:%02d", reminder.hour, reminder.minute)).monospacedDigit()
                        }
                    } label: {
                        Label { Text(goal.name) } icon: { GoalIcon(goal: goal, size: 20) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
        .task { await scheduler.refreshAuthorization() }
    }
}

private extension UNAuthorizationStatus {
    var text: String {
        switch self {
        case .authorized: "Allowed"
        case .denied: "Turned off in System Settings"
        case .provisional: "Delivered quietly"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }
}

private struct DataSettings: View {
    @Environment(GoalStore.self) private var store
    @State private var exportingJSON = false
    @State private var exportingCSV = false
    @State private var importing = false
    @State private var pendingImport: AppData?
    @State private var message: String?
    /// The daily copies, listed when the tab appears rather than on every redraw.
    @State private var backups: [URL] = []

    var body: some View {
        Form {
            Section("Export") {
                LabeledContent("Full backup") {
                    Button("Export JSON…") { exportingJSON = true }
                }
                LabeledContent("Spreadsheet of every entry") {
                    Button("Export CSV…") { exportingCSV = true }
                }
            }
            Section("Import") {
                LabeledContent("Restore a JSON backup") {
                    Button("Import…") { importing = true }
                }
                Text("Importing replaces everything. The current data is kept as a backup file first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Automatic backups") {
                LabeledContent("Daily copies kept", value: "\(backups.count) of 14")
                LabeledContent("Restore a daily copy") {
                    Button("Choose…") { chooseBackup(in: backups) }
                        .disabled(backups.isEmpty)
                }
            }
            Section("Storage") {
                LabeledContent("Goals", value: "\(store.data.goals.count)")
                LabeledContent("Entries", value: "\(store.data.entries.count)")
                Text("Everything stays on this Mac, in Momentum's app group container. The only network request is a book search you type, sent to Open Library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
        .onAppear { backups = store.dailyBackups }
        .fileExporter(isPresented: $exportingJSON, document: ExportDocument(store.data, kind: .backup),
                      contentType: .json, defaultFilename: "Momentum Backup \(Date.now.formatted(.iso8601.year().month().day()))") { result in
            report(result, what: "Backup")
        }
        .fileExporter(isPresented: $exportingCSV, document: ExportDocument(store.data, kind: .entries),
                      contentType: .commaSeparatedText, defaultFilename: "Momentum Entries") { result in
            report(result, what: "CSV")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                do {
                    pendingImport = try FileStore.decode(Data(contentsOf: url))
                } catch {
                    message = "That file isn't a Momentum backup: \(error.localizedDescription)"
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Replace all data?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), presenting: pendingImport) { data in
            Button("Replace with \(data.goals.count) goals", role: .destructive) {
                store.replaceAll(with: data)
                message = "Imported \(data.goals.count) goals and \(data.entries.count) entries."
            }
        } message: { _ in
            Text("Your current goals and history will be replaced. A backup of them is saved first.")
        }
    }

    /// Picks one of the daily copies; restoring goes through the same confirmation as an import.
    private func chooseBackup(in backups: [URL]) {
        let panel = NSOpenPanel()
        panel.directoryURL = backups.first?.deletingLastPathComponent()
        panel.allowedContentTypes = [.json]
        panel.prompt = "Restore"
        panel.message = "Choose a daily copy to restore."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingImport = try FileStore.decode(Data(contentsOf: url))
        } catch {
            message = "That copy can't be read: \(error.localizedDescription)"
        }
    }

    private func report(_ result: Result<URL, Error>, what: String) {
        switch result {
        case .success(let url): message = "\(what) saved to \(url.lastPathComponent)."
        case .failure(let error): message = error.localizedDescription
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Momentum")
                .font(.title.weight(.bold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("Goals, focus sessions, streaks and reading, with widgets on your desktop.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("github.com/Leeevai/momentum", destination: URL(string: "https://github.com/Leeevai/momentum")!)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .frame(height: 380)
    }
}
