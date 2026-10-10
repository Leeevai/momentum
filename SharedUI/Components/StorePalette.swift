import MomentumCore
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Draws a window's views in the palette chosen in Settings.
private struct StorePalette: ViewModifier {
    @Environment(GoalStore.self) private var store

    func body(content: Content) -> some View {
        #if os(iOS)
        content.palette(store.palette)
            .onAppear { WindowTint.apply(store.palette) }
            .onChange(of: store.palette) { _, palette in WindowTint.apply(palette) }
        #else
        content.palette(store.palette)
        #endif
    }
}

#if os(iOS)
/// Alerts, confirmation dialogs, swipe actions and the text cursor take the window's tint rather
/// than SwiftUI's, so it follows the palette too. Elsewhere the asset's accent stands in: the
/// default palette's.
@MainActor
private enum WindowTint {
    static func apply(_ palette: Palette) {
        let tint = UIColor(palette.colors.accent)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.tintColor = tint }
        }
    }
}
#endif

extension View {
    /// Draws this window in the chosen palette. Apply inside `.environment(store)`.
    func storePalette() -> some View {
        modifier(StorePalette())
    }
}
