import MomentumCore
import SwiftUI

/// The ground every screen sits on. In light mode, the palette's base color, flat; a goal's screen
/// passes its color, which tints the ground by a breath so the page reads as that goal's. In dark
/// mode, pure black, AMOLED style, on every screen. Named for the drifting aurora it replaced; the
/// palette still calls its base the aurora's.
struct Aurora: View {
    /// A goal's color, faintly mixed into the ground.
    var accent: Color?

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let base = Color(palette.tokens(dark: false).auroraBase)
        Group {
            if colorScheme == .dark {
                Color.black
            } else if let accent {
                base.blended(with: accent, by: 0.04)
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
