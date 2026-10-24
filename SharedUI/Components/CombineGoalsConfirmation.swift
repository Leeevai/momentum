import MomentumCore
import SwiftUI

extension View {
    /// Asks before one goal goes into another, from Combine Into in a goal's menu.
    func combineGoalsConfirmation(_ store: GoalStore) -> some View {
        modifier(CombineGoalsConfirmation(store: store))
    }
}

private struct CombineGoalsConfirmation: ViewModifier {
    let store: GoalStore

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible, presenting: store.confirmingCombine) { combination in
            Button("Combine", role: .destructive) { store.combine(combination.source, into: combination.target) }
        } message: { combination in
            Text(message(for: combination))
        }
    }

    private var title: String {
        guard let combination = store.confirmingCombine else { return "Combine goals?" }
        return "Combine \(combination.source.name) into \(combination.target.name)?"
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { store.confirmingCombine != nil }, set: { if !$0 { store.confirmingCombine = nil } })
    }

    private func message(for combination: GoalCombination) -> String {
        let source = combination.source
        let target = combination.target
        let logs = store.data.entries.count(where: { $0.goalID == source.id })
        let history = logs == 1 ? "Its log" : "Its \(logs) logs"
        var text = "\(history), milestones, books and links move to \(target.name), which keeps its own target and schedule. "
            + "\(source.name) is removed on all your devices."
        #if os(macOS)
        text += " You can undo it with ⌘Z."
        #endif
        return text
    }
}
