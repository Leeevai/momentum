import AppKit
import SwiftUI

extension View {
    /// In dark mode, lets the window's title bar and toolbar show the black screens under them,
    /// with no line beneath, so the whole window is one pure black; light mode keeps the system's
    /// title bar.
    func darkWindowChrome() -> some View {
        modifier(DarkWindowChrome())
    }
}

private struct DarkWindowChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(TitleBarStyler(isBlack: colorScheme == .dark))
    }
}

/// Styles the window it sits in. Set on the window itself: SwiftUI's toolbar background settings
/// leave the detail column's title bar material in place on macOS 26 and later.
private struct TitleBarStyler: NSViewRepresentable {
    var isBlack: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // The view joins its window after the first update.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = isBlack
            window.titlebarSeparatorStyle = isBlack ? .none : .automatic
            window.backgroundColor = isBlack ? .black : .windowBackgroundColor
        }
    }
}
