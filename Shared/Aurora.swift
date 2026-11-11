import MomentumCore
import SwiftUI

/// The ground every screen sits on: the palette's base color, flat. A goal's screen passes its
/// color, which tints the ground by a breath so the page reads as that goal's without a gradient.
/// Named for the drifting aurora it replaced; the palette still calls its base the aurora's.
struct Aurora: View {
    /// A goal's color, faintly mixed into the ground.
    var accent: Color?

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let base = Color(palette.tokens(dark: dark).auroraBase)
        Group {
            if let accent {
                base.blended(with: accent, by: dark ? 0.06 : 0.04)
            } else {
                base
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.4), value: palette)
    }
}
