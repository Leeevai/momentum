import MomentumCore
import SwiftUI

/// Menus and keyboard shortcuts for iPad with a keyboard: the iPadOS menu bar, and the list
/// that shows while Command is held. The same shortcuts as on the Mac.
struct MobileCommands: Commands {
    let store: GoalStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Goal") { store.sheet = .newGoal }
                .keyboardShortcut("n", modifiers: .command)
            Button("To-dos from Videos") { store.sheet = .importTodos(link: nil) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        CommandMenu("Go") {
            Button("Today") { store.route = .today }
                .keyboardShortcut("1", modifiers: .command)
            Button("Journal") { store.route = .journal }
                .keyboardShortcut("2", modifiers: .command)
            Button("Insights") { store.route = .insights }
                .keyboardShortcut("3", modifiers: .command)
            Button("Awards") { store.route = .awards }
                .keyboardShortcut("4", modifiers: .command)
            Divider()
            ForEach(Array(store.engine.activeGoals.prefix(5).enumerated()), id: \.element.id) { index, goal in
                Button { store.select(goal.id) } label: { Label(goal.name, systemImage: goal.symbol) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 5))), modifiers: .command)
            }
        }
        CommandMenu("Focus") {
            if let session = store.data.session, let goal = store.goal(session.goalID) {
                Button(session.isRunning ? "Pause \(goal.name)" : "Resume \(goal.name)") { store.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Stop and Save") { store.stopFocus() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Focus Mode") { store.isFocusModePresented = true }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                if session.plannedDuration != nil {
                    Button("Add 5 Minutes") { store.extendFocus(by: 5) }
                }
            } else if let rest = store.data.rest, let goal = store.goal(rest.goalID) {
                Button("Start Block \(rest.nextBlock) of \(goal.name)") { store.startNextBlock() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button(rest.isOver(at: .now) ? "Done for Now" : "Skip Break") { store.endRest() }
            } else {
                ForEach(store.engine.activeGoals.filter { $0.kind == .time }) { goal in
                    Button { store.toggleFocus(goal) } label: { Label("Start \(goal.name)", systemImage: goal.symbol) }
                }
            }
        }
        CommandMenu("Journal") {
            Button("Plan Today") { store.sheet = .plan(DayID(.now)) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Reflect on Today") { store.sheet = .reflect(DayID(.now)) }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button("Week in Review") { store.sheet = .review }
                .keyboardShortcut("w", modifiers: [.command, .option])
        }
    }
}
