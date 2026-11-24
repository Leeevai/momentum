import MomentumCore
import SwiftUI

extension GoalColor {
    /// The color as `goal.tint` and the named roles draw it: the active palette's swatch in a
    /// shade that reads as text on a pane (4.5:1), since that's mostly what they color. Rings,
    /// bars, tiles and glyphs draw the swatch itself, through `palette.color(_:)` or `swatch`.
    var color: Color { ActivePalette.colors.text(self) }

    /// The active palette's swatch itself, for rings, bars and glyphs, and for a fill whose label
    /// is chosen by its color.
    var swatch: Color { ActivePalette.colors.swatch(self) }

    /// A lighter companion of the swatch.
    var highlight: Color { ActivePalette.colors.highlight(self) }

    /// A deep shade of the color that white symbols read on, in light and dark.
    var tile: Color { ActivePalette.current.tile(self) }

    /// The deep shade on its own.
    var deep: Color { ActivePalette.colors.deep(self) }

    /// A fill for a label, white or black (`Color.foreground(in:)` of the swatch): the swatch.
    var fill: Color { swatch }
}

extension Palette {
    /// A goal color's swatch.
    func color(_ goalColor: GoalColor) -> Color {
        colors.swatch(goalColor)
    }

    /// A goal color deep enough for white symbols on it: icon tiles, medals, kept days. In
    /// light mode it's the swatch itself; in dark mode, where swatches are light, a deeper shade.
    func tile(_ goalColor: GoalColor) -> Color {
        colors.deep(goalColor)
    }
}

extension Goal {
    var tint: Color { color.color }
}

extension Mood {
    var tint: Color { goalColor.color }

    /// The palette color a mood is drawn in: cool for a rough day, warm for a great one.
    var goalColor: GoalColor {
        switch self {
        case .rough: .purple
        case .low: .blue
        case .okay: .gray
        case .good: .teal
        case .great: .orange
        }
    }
}

extension Energy {
    var tint: Color { goalColor.color }

    /// The palette color an energy level is drawn in, from red when drained to mint when charged.
    var goalColor: GoalColor {
        switch self {
        case .drained: .red
        case .low: .orange
        case .steady: .yellow
        case .high: .green
        case .charged: .mint
        }
    }
}

/// The app's own accents, from the active palette, so nothing on screen falls back to a system
/// color the palette doesn't have. Errors and warnings keep the system's red and orange.
extension ShapeStyle where Self == Color {
    /// A goal color's swatch, for an accent that isn't a goal's.
    static func swatch(_ goalColor: GoalColor) -> Color { goalColor.color }
    /// Streaks and their flames.
    static var streak: Color { GoalColor.orange.color }
    /// Done, on track, a gain.
    static var success: Color { GoalColor.green.color }
    /// Behind, overdue, urgent: a nudge rather than an error.
    static var attention: Color { GoalColor.orange.color }
    /// Focus time and the timer.
    static var focus: Color { GoalColor.indigo.color }
    /// Awards, bests and ratings.
    static var award: Color { GoalColor.yellow.color }
    /// Breaks between focus blocks.
    static var rest: Color { GoalColor.mint.color }
}

extension Color {
    /// Blends two colors: perceptually on macOS 15 and iOS 18 and later, in sRGB before that.
    func blended(with other: Color, by fraction: Double) -> Color {
        if #available(macOS 15.0, iOS 18.0, *) {
            return self.mix(with: other, by: fraction, in: .perceptual)
        }
        #if canImport(AppKit)
        let lhs = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let rhs = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        let mixed = lhs.blended(withFraction: fraction, of: rhs) ?? lhs
        return Color(nsColor: mixed)
        #else
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(fraction)
        return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
        #endif
    }
}

extension Color {
    /// The window's background: behind content, and the base glass is laid over.
    static var windowBackground: Color {
        #if canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

extension View {
    /// Runs `action` on Escape (macOS); a no-op where there is no Escape key to speak of.
    @ViewBuilder
    func onEscape(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}
