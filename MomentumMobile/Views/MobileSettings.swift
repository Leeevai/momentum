import MomentumCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings on iPhone: focus and Pomodoro, sync, journal and feedback.
struct MobileSettings: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picksFolder = false
    /// The volume while the slider is dragged; saved when it's let go, not on every step.
    @State private var volume: Double?

    var body: some View {
        let preferences = store.data.preferences
        let pomodoro = preferences.pomodoro
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ManageGoalsView()
                    } label: {
                        LabeledContent {
                            Text("\(store.engine.activeGoals.count)")
                        } label: {
                            Label("Goals", systemImage: "list.bullet")
                        }
                    }
                } footer: {
                    Text("Reorder, archive and restore goals.")
                }
                Section("Focus") {
                    Picker("Default session length", selection: binding(\.defaultFocusMinutes, preferences)) {
                        ForEach(FocusLengthMenu.lengths, id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                    Toggle("Ask how each session went", isOn: binding(\.asksSessionQuality, preferences))
                    Picker("Focus sound", selection: binding(\.focusSound, preferences)) {
                        ForEach(FocusSound.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                    }
                    if preferences.focusSound != .off {
                        Slider(value: Binding(get: { volume ?? preferences.focusSoundVolume }, set: { volume = $0 }), in: 0.05...1) {
                            Text("Volume")
                        } onEditingChanged: { editing in
                            guard !editing, let volume else { return }
                            store.updatePreferences { $0.focusSoundVolume = volume }
                            self.volume = nil
                        }
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
                }
                MobileNotificationsSection()
                MobileDataSection()
                Section("Feedback") {
                    Toggle("Celebrate finished goals", isOn: binding(\.celebratesCompletion, preferences))
                    Toggle("Haptics", isOn: binding(\.playsSounds, preferences))
                }
                Section {
                    HStack(spacing: 14) {
                        MomentumMark(size: 44, animated: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Momentum")
                                .font(.headline)
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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

/// Export a backup or a spreadsheet, import a backup, or restore one of the daily copies.
/// Reminders, the evening nudge and its time, the weekly recap, and whether notifications are
/// allowed at all, with the way to Settings when they aren't.
private struct MobileNotificationsSection: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.openURL) private var openURL

    var body: some View {
        let preferences = store.data.preferences
        let scheduler = store.effects.notifications
        Section {
            Toggle("Goal reminders", isOn: binding(\.remindersEnabled, preferences))
            Toggle("Evening nudge", isOn: binding(\.streakNudgesEnabled, preferences))
            if preferences.streakNudgesEnabled {
                DatePicker("Nudge at", selection: nudgeTime(preferences), displayedComponents: .hourAndMinute)
            }
            Toggle("Weekly recap", isOn: binding(\.weeklyRecapEnabled, preferences))
            switch scheduler.authorization {
            case .notDetermined:
                Button("Allow Notifications") { Task { await scheduler.requestAuthorization() } }
            case .denied:
                Button("Turn On in Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            default:
                EmptyView()
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(scheduler.authorization == .denied
                 ? "Notifications are off for Momentum, so reminders and nudges can't arrive."
                 : "The evening nudge comes when a streak or a challenge day would end at midnight.")
        }
        .task { await scheduler.refreshAuthorization() }
    }

    private func nudgeTime(_ preferences: Preferences) -> Binding<Date> {
        Binding(
            get: {
                let minute = preferences.streakNudgeMinute
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.updatePreferences { $0.streakNudgeMinute = (parts.hour ?? 20) * 60 + (parts.minute ?? 0) }
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Preferences, Value>, _ preferences: Preferences) -> Binding<Value> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in store.updatePreferences { $0[keyPath: keyPath] = value } })
    }
}

private struct MobileDataSection: View {
    @Environment(GoalStore.self) private var store
    @State private var exportingJSON = false
    @State private var exportingCSV = false
    @State private var importing = false
    @State private var pendingImport: AppData?
    @State private var message: String?
    /// The daily copies, listed when the section appears rather than on every redraw.
    @State private var backups: [URL] = []

    var body: some View {
        Section {
            Button { exportingJSON = true } label: { Label("Export a Backup", systemImage: "square.and.arrow.up") }
            Button { exportingCSV = true } label: { Label("Export Entries as CSV", systemImage: "tablecells") }
            Button { importing = true } label: { Label("Import a Backup", systemImage: "square.and.arrow.down") }
            if !backups.isEmpty {
                Menu {
                    ForEach(backups, id: \.self) { url in
                        Button(Self.title(for: url)) { load(url) }
                    }
                } label: {
                    Label("Restore a Daily Copy", systemImage: "clock.arrow.circlepath")
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("\(store.data.goals.count) goals and \(store.data.entries.count) entries, kept on this iPhone. Importing replaces everything, and saves the current data as a backup first.")
        }
        .fileExporter(isPresented: $exportingJSON, document: ExportDocument(store.data, kind: .backup),
                      contentType: .json, defaultFilename: "Momentum Backup \(Date.now.formatted(.iso8601.year().month().day()))") { result in
            report(result, what: "Backup")
        }
        .fileExporter(isPresented: $exportingCSV, document: ExportDocument(store.data, kind: .entries),
                      contentType: .commaSeparatedText, defaultFilename: "Momentum Entries") { result in
            report(result, what: "CSV")
        }
        .onAppear { backups = store.dailyBackups }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): message = error.localizedDescription
            }
        }
        .confirmationDialog("Replace all data?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible, presenting: pendingImport) { data in
            Button("Replace with \(data.goals.count) goals", role: .destructive) {
                store.replaceAll(with: data)
                message = "Restored \(data.goals.count) goals and \(data.entries.count) entries."
            }
        } message: { _ in
            Text("Your current goals and history will be replaced. A backup of them is saved first.")
        }
    }

    private func load(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingImport = try FileStore.decode(Data(contentsOf: url))
        } catch {
            message = "That file isn't a Momentum backup: \(error.localizedDescription)"
        }
    }

    private func report(_ result: Result<URL, Error>, what: String) {
        switch result {
        case .success(let url): message = "\(what) saved to \(url.lastPathComponent)."
        case .failure(let error): message = error.localizedDescription
        }
    }

    /// "data-2026-10-08.json" as "Thursday 8 October".
    private static func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "data-", with: "")
        guard let day = DayID(string: name) else { return name }
        return day.date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}
