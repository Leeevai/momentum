import SwiftUI

/// Draws a window's views in the palette chosen in Settings.
private struct StorePalette: ViewModifier {
    @Environment(GoalStore.self) private var store

    func body(content: Content) -> some View {
        content.palette(store.palette)
    }
}

extension View {
    /// Draws this window in the chosen palette. Apply inside `.environment(store)`.
    func storePalette() -> some View {
        modifier(StorePalette())
    }
}
