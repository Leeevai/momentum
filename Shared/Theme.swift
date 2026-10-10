import MomentumCore
import SwiftUI

extension GoalColor {
    /// The active palette's swatch for this color.
    var color: Color { ActivePalette.colors.swatch(self) }

    /// A lighter companion hue for gradients.
    var highlight: Color { ActivePalette.colors.highlight(self) }

    /// The ring's sweep: from the light companion into the full color.
    var gradient: AngularGradient { ActivePalette.current.ringGradient(self) }

    /// The color as a soft diagonal gradient, for symbols, bars and swatches drawn in it.
    var linear: LinearGradient { ActivePalette.current.linear(self) }

    /// A deep shade of the color that white symbols read on, in light and dark.
    var tile: LinearGradient { ActivePalette.current.tile(self) }

    /// The deep shade on its own, flat.
    var deep: Color { ActivePalette.colors.deep(self) }

    /// A fill for a label: from the swatch away from the label's color, so text in white or black
    /// (`Color.foreground(in:)` of the swatch) holds 4.5:1 across it.
    var fill: LinearGradient { ActivePalette.current.fill(self) }
}

extension Palette {
    /// A goal color's swatch.
    func color(_ goalColor: GoalColor) -> Color {
        colors.swatch(goalColor)
    }

    /// A ring's sweep in a goal color: from its highlight into the full color.
    func ringGradient(_ goalColor: GoalColor) -> AngularGradient {
        let shades = colors
        let swatch = shades.swatch(goalColor)
        return AngularGradient(colors: [shades.highlight(goalColor), swatch, swatch], center: .center,
                               startAngle: .degrees(0), endAngle: .degrees(360))
    }

    /// A goal color as a soft diagonal gradient, for symbols, bars and swatches drawn in it.
    func linear(_ goalColor: GoalColor) -> LinearGradient {
        let shades = colors
        return LinearGradient(colors: [shades.highlight(goalColor), shades.swatch(goalColor)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A goal color as a label's fill: from the swatch away from its label's color.
    func fill(_ goalColor: GoalColor) -> LinearGradient {
        let shades = colors
        return LinearGradient(colors: [shades.swatch(goalColor), shades.fillEnd(goalColor)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A goal color deep enough for white symbols on it: icon tiles, medals, kept days. In
    /// light mode it's the swatch itself; in dark mode, where swatches are light, a deeper shade.
    func tile(_ goalColor: GoalColor) -> LinearGradient {
        let shades = colors
        return LinearGradient(colors: [shades.deepHighlight(goalColor), shades.deep(goalColor)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
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
