import MomentumCore
import SwiftUI

// The app's look follows glasscn (https://glasscn.app, MIT license, copyright 2026 Tim
// Mikeladze): frosted panes with a light rim over a drifting aurora, in one of its palettes.

extension Color {
    /// A palette color, defined in OKLCH.
    init(_ oklch: OKLCH, opacity: Double = 1) {
        let rgb = oklch.sRGB
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }

    /// The palette's accent, resolved for light or dark each time it's drawn. In place of
    /// `accentColor` wherever a `Color` is needed rather than the `.tint` style.
    static var accent: Color {
        dynamic { ActivePalette.current.tokens(dark: $0).accent }
    }

    /// A color that follows the appearance it's drawn in.
    static func dynamic(_ resolve: @escaping @Sendable (_ dark: Bool) -> OKLCH) -> Color {
        #if canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = resolve(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua).sRGB
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            let rgb = resolve(traits.userInterfaceStyle == .dark).sRGB
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        #endif
    }
}

/// The palette the app is drawn in, for colors resolved outside the view tree. Set by the store
/// from preferences; views read the `palette` environment value.
enum ActivePalette {
    nonisolated(unsafe) static var current: ThemePalette = .dusk
}

extension EnvironmentValues {
    @Entry var palette: ThemePalette = .dusk
}

extension View {
    /// Draws this tree in `palette`: its accent as the tint, its aurora behind screens.
    func palette(_ palette: ThemePalette) -> some View {
        environment(\.palette, palette)
            .tint(Color.dynamic { palette.tokens(dark: $0).accent })
    }
}

/// glasscn's glass in numbers (its glass-style tokens): how much a pane frosts, the rim and
/// highlight on its edge, and its shadow, in light and dark.
struct GlassTokens {
    /// The pane's own tint over the blur: default, strong (dialogs, menus) and subtle.
    let fill: Color
    let strongFill: Color
    let subtleFill: Color
    /// The 1-point edge, and the brighter line along its top.
    let rim: Color
    let highlight: Color
    /// The diagonal sheen across the top-leading corner.
    let sheen: Double
    let shadow: Color
    /// Tint laid into Liquid Glass so panes read on a pale aurora.
    let liquidTint: Color
    /// Neutral fill for secondary controls, tracks and wells.
    let controlFill: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            let tint = OKLCH(0.24, 0.012, 285)
            fill = Color(tint, opacity: 0.45)
            strongFill = Color(tint, opacity: 0.72)
            subtleFill = Color(tint, opacity: 0.24)
            rim = .white.opacity(0.12)
            highlight = .white.opacity(0.14)
            sheen = 0.05
            shadow = .black.opacity(0.45)
            liquidTint = Color(.sRGB, red: 30 / 255, green: 30 / 255, blue: 38 / 255, opacity: 0.4)
            controlFill = Color(OKLCH(0.6, 0.01, 285), opacity: 0.24)
        } else {
            fill = .white.opacity(0.52)
            strongFill = .white.opacity(0.74)
            subtleFill = .white.opacity(0.28)
            rim = .white.opacity(0.85)
            highlight = .white.opacity(0.92)
            sheen = 0.10
            shadow = Color(OKLCH(0.3, 0.05, 270), opacity: 0.12)
            liquidTint = .white.opacity(0.45)
            controlFill = Color(OKLCH(0.55, 0.01, 285), opacity: 0.12)
        }
    }

    /// Panes and cards.
    static let surfaceRadius: CGFloat = 24
    /// Fields, tiles and other controls that aren't capsules.
    static let controlRadius: CGFloat = 12
    /// glasscn's 10-point drop and 30-point blur, as SwiftUI measures shadows.
    static let shadowRadius: CGFloat = 15
    static let shadowY: CGFloat = 10
    /// How far a press squashes a control.
    static let pressScale: CGFloat = 0.97
    /// glasscn's easing, cubic-bezier(0.2, 0.9, 0.3, 1.12) over 200 ms: quick, a touch of overshoot.
    static let motion = Animation.timingCurve(0.2, 0.9, 0.3, 1.12, duration: 0.2)
}
