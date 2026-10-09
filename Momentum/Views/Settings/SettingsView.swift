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
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
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
            Section("Focus") {
                Picker("Default session length", selection: binding(\.defaultFocusMinutes, preferences)) {
                    ForEach(FocusLengthMenu.lengths, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Text("Used by Shortcuts and Siri when no length is given. Each goal can set its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Feedback") {
                Toggle("Celebrate finished goals with confetti", isOn: binding(\.celebratesCompletion, preferences))
                Toggle("Play sounds", isOn: binding(\.playsSounds, preferences))
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>, _ preferences: Preferences) -> Binding<Value> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } })
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
                    LabeledContent("\(goal.icon) \(goal.name)") {
                        if let reminder = goal.reminder {
                            Text(String(format: "%02d:%02d", reminder.hour, reminder.minute)).monospacedDigit()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
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
            Section("Storage") {
                LabeledContent("Goals", value: "\(store.data.goals.count)")
                LabeledContent("Entries", value: "\(store.data.entries.count)")
                Text("Everything stays on this Mac, in Momentum's app group container. Nothing is sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 380)
        .fileExporter(isPresented: $exportingJSON, document: ExportDocument(data: (try? FileStore.encode(store.data)) ?? Data(), type: .json),
                      contentType: .json, defaultFilename: "Momentum Backup \(Date.now.formatted(.iso8601.year().month().day()))") { result in
            report(result, what: "Backup")
        }
        .fileExporter(isPresented: $exportingCSV, document: ExportDocument(data: Data(CSVExporter.csv(for: store.data).utf8), type: .commaSeparatedText),
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

    private func report(_ result: Result<URL, Error>, what: String) {
        switch result {
        case .success(let url): message = "\(what) saved to \(url.lastPathComponent)."
        case .failure(let error): message = error.localizedDescription
        }
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    var type: UTType

    init(data: Data, type: UTType) {
        self.data = data
        self.type = type
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        type = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
