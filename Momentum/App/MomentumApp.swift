import AppKit
import MomentumCore
import SwiftUI

@main
struct MomentumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = GoalStore()

    var body: some Scene {
        Window("Momentum", id: "main") {
            RootView()
                .environment(store)
                .frame(minWidth: 880, minHeight: 600)
                .onOpenURL { url in handle(url) }
        }
        .defaultSize(width: 1180, height: 800)
        .windowToolbarStyle(.unified)
        .commands { MomentumCommands(store: store) }

        Settings {
            SettingsView()
                .environment(store)
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }

    private func handle(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .today: store.route = .today
        case .insights: store.route = .insights
        case .goal(let id): store.select(id)
        case .newGoal: store.sheet = .newGoal
        case .openLink(let goalID, let linkID):
            if let link = store.goal(goalID)?.links.first(where: { $0.id == linkID }) {
                LinkOpener.open(link)
            }
            store.select(goalID)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keep running in the menu bar after the window closes, so a focus timer stays visible.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with no window open brings the main window back. The menu-bar
    /// item is always alive, so it listens for this and opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .reopenMainWindow, object: nil) }
        return true
    }
}


struct MomentumCommands: Commands {
    let store: GoalStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Goal…") {
                openWindow(id: "main")
                store.sheet = .newGoal
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu("Go") {
            Button("Quick Actions…") {
                openWindow(id: "main")
                store.sheet = .quickActions
            }
            .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Today") { show(.today) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Insights") { show(.insights) }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
            ForEach(Array(store.engine.activeGoals.prefix(7).enumerated()), id: \.element.id) { index, goal in
                Button("\(goal.icon) \(goal.name)") { show(.goal(goal.id)) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 3))), modifiers: .command)
            }
        }
        CommandGroup(replacing: .help) {
            Button("Momentum Help") { showHelp() }
            Button("Report an Issue…") {
                if let url = URL(string: "https://github.com/Leeevai/momentum/issues/new/choose") { NSWorkspace.shared.open(url) }
            }
        }
        CommandMenu("Focus") {
            if let session = store.data.session, let goal = store.goal(session.goalID) {
                Button(session.isRunning ? "Pause \(goal.name)" : "Resume \(goal.name)") { store.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Stop and Save") { store.stopFocus() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                if session.plannedDuration != nil {
                    Button("Add 5 Minutes") { store.extendFocus(by: 5) }
                }
                Divider()
                Button("Discard Session") { store.discardFocus() }
            } else {
                let timeGoals = store.engine.activeGoals.filter { $0.kind == .time }
                if timeGoals.isEmpty {
                    Text("No time goals yet")
                }
                ForEach(timeGoals) { goal in
                    Button("Start \(goal.icon) \(goal.name)") { store.toggleFocus(goal) }
                }
            }
        }
    }

    private func showHelp() {
        if let url = URL(string: "https://github.com/Leeevai/momentum#readme") { NSWorkspace.shared.open(url) }
    }

    private func show(_ route: Route) {
        openWindow(id: "main")
        store.route = route
    }
}
