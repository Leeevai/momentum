import MomentumCore
import SwiftUI

// The app's palettes follow glasscn's themes (https://glasscn.app, MIT license, copyright 2026 Tim
// Mikeladze), drawn minimally: flat panes on a plain ground faintly tinted by the palette.

extension Color {
    /// A palette color, defined in OKLCH.
    init(_ oklch: OKLCH, opacity: Double = 1) {
        let rgb = oklch.sRGB
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }

    /// The palette's accent, resolved for light or dark each time it's drawn. In place of
    /// `accentColor` wherever a `Color` is needed rather than the `.tint` style.
    static var accent: Color { ActivePalette.colors.accent }

    /// A color that is `light` in light mode and `dark` in dark mode. The name tells colors of
    /// different palettes apart wherever SwiftUI compares them, so a view redraws in a new one.
    static func dynamic(named name: String, light: OKLCH, dark: OKLCH) -> Color {
        let lightRGB = light.sRGB
        let darkRGB = dark.sRGB
        #if canImport(AppKit)
        return Color(nsColor: NSColor(name: name) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkRGB : lightRGB
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        #else
        return Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? darkRGB : lightRGB
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
        #endif
    }

    /// Text and symbols on a fill of this color: white, or black where black reads better. Of
    /// the two, one always reaches WCAG's 4.5:1.
    func foreground(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.linearRed) + 0.7152 * Double(resolved.linearGreen) + 0.0722 * Double(resolved.linearBlue)
        // Where white and black contrast equally: (L + 0.05)² = 1.05 × 0.05.
        return luminance > 0.179 ? .black : .white
    }
}

/// The palette the app is drawn in, for colors resolved outside the view tree. Set by the store
/// from preferences, and by the widgets when they read the data file; views read the `palette`
/// environment value. Behind a lock: a widget extension loads several timelines at once.
enum ActivePalette {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var palette = Palette.standard
    nonisolated(unsafe) private static var surface = TextSurface.glass
    nonisolated(unsafe) private static var paletteColors = PaletteColors(.standard)

    static var current: Palette {
        get { lock.withLock { palette } }
        set {
            lock.withLock {
                guard newValue != palette else { return }
                palette = newValue
                paletteColors = PaletteColors(newValue, text: surface)
            }
        }
    }

    /// What text sits on in this process: glass panes in the apps, the bare aurora in widgets.
    static var textSurface: TextSurface {
        get { lock.withLock { surface } }
        set {
            lock.withLock {
                guard newValue != surface else { return }
                surface = newValue
                paletteColors = PaletteColors(palette, text: newValue)
            }
        }
    }

    /// `current` as SwiftUI colors, made once per palette rather than on every use.
    static var colors: PaletteColors { lock.withLock { paletteColors } }

    /// The active palette's colors, if `palette` is the active one.
    static func colors(for palette: Palette) -> PaletteColors? {
        lock.withLock { palette == self.palette ? paletteColors : nil }
    }
}

/// A palette's colors as SwiftUI colors: the accent and, for every goal color, its swatch, a
/// lighter highlight and a deep shade that white symbols read on.
struct PaletteColors: Sendable {
    let accent: Color
    private let swatches: [GoalColor: Color]
    private let highlights: [GoalColor: Color]
    private let deepShades: [GoalColor: Color]
    private let deepHighlights: [GoalColor: Color]
    /// Each swatch as text: deeper in light mode and lighter in dark, until it reads on glass.
    private let textShades: [GoalColor: Color]
    private let fillEnds: [GoalColor: Color]

    init(_ palette: Palette, text surface: TextSurface = .glass) {
        // The palette's content in every name, so an edited custom palette doesn't pass for the
        // one it was.
        let key = "momentum.\(palette.id).\(palette.hashValue)"
        func colors(_ kind: String, _ shade: (OKLCH) -> OKLCH) -> [GoalColor: Color] {
            Dictionary(uniqueKeysWithValues: GoalColor.allCases.map { goalColor in
                (goalColor, Color.dynamic(named: "\(key).\(kind).\(goalColor.rawValue)",
                                          light: shade(palette.light.swatch(goalColor)), dark: shade(palette.dark.swatch(goalColor))))
            })
        }
        accent = .dynamic(named: "\(key).accent", light: palette.light.accent, dark: palette.dark.accent)
        swatches = colors("swatch") { $0 }
        highlights = colors("highlight") { $0.highlight }
        deepShades = colors("deep") { $0.deepened }
        deepHighlights = colors("deep-highlight") { OKLCH($0.deepened.lightness + 0.04, $0.deepened.chroma, $0.hue).inSRGB }
        textShades = Dictionary(uniqueKeysWithValues: GoalColor.allCases.map { goalColor in
            (goalColor, Color.dynamic(named: "\(key).text.\(goalColor.rawValue)",
                                      light: palette.light.swatch(goalColor).readable(onLuminance: surface.luminance(dark: false)),
                                      dark: palette.dark.swatch(goalColor).readable(onLuminance: surface.luminance(dark: true))))
        })
        // A label's fill shades away from the label, so it keeps its contrast across the fill.
        fillEnds = colors("fill-end") { OKLCH($0.lightness + ($0.prefersDarkLabel ? 0.05 : -0.05), $0.chroma, $0.hue).inSRGB }
    }

    func swatch(_ color: GoalColor) -> Color { swatches[color] ?? .gray }
    func highlight(_ color: GoalColor) -> Color { highlights[color] ?? .gray }
    func deep(_ color: GoalColor) -> Color { deepShades[color] ?? .gray }
    func deepHighlight(_ color: GoalColor) -> Color { deepHighlights[color] ?? .gray }
    func text(_ color: GoalColor) -> Color { textShades[color] ?? .gray }
    func fillEnd(_ color: GoalColor) -> Color { fillEnds[color] ?? .gray }
}

extension Palette {
    /// The palette as SwiftUI colors: the active palette's are made once, and those of a few
    /// others (the picker's, a palette being edited) are kept while they're in use.
    var colors: PaletteColors {
        ActivePalette.colors(for: self) ?? PaletteColorCache.colors(for: self)
    }
}

/// Colors of the palettes drawn besides the active one, so a picker or a live preview doesn't
/// make them again on every redraw.
private enum PaletteColorCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Palette: PaletteColors] = [:]

    static func colors(for palette: Palette) -> PaletteColors {
        lock.lock()
        defer { lock.unlock() }
        if let colors = cache[palette] { return colors }
        // A palette being edited changes on every drag of a slider: start over now and then.
        if cache.count >= 24 { cache.removeAll() }
        let colors = PaletteColors(palette)
        cache[palette] = colors
        return colors
    }
}

private struct PaletteKey: EnvironmentKey {
    /// Outside a `palette(_:)` modifier, the active palette.
    static var defaultValue: Palette { ActivePalette.current }
}

extension EnvironmentValues {
    /// The palette views below are drawn in.
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Draws this tree in `palette`: its accent as the tint, its aurora behind screens, its
    /// swatches for goal colors.
    func palette(_ palette: Palette) -> some View {
        environment(\.palette, palette)
            .tint(palette.colors.accent)
    }
}

/// The look in numbers: a pane's fill and hairline, the fill of quiet controls, radii and motion,
/// in light and dark. Panes are flat: no blur, sheen, glow or shadow, so color is left to the
/// goals' rings and the one main action on a screen.
struct GlassTokens {
    /// A pane's fill, a step off the screen's ground: lighter in light mode, lighter in dark.
    let fill: Color
    /// A quieter fill, for wells and rows inside a pane.
    let subtleFill: Color
    /// The pane's hairline edge.
    let rim: Color
    /// Neutral fill for secondary controls, tracks and wells.
    let controlFill: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            fill = .white.opacity(0.055)
            subtleFill = .white.opacity(0.035)
            rim = .white.opacity(0.07)
            controlFill = .white.opacity(0.09)
        } else {
            fill = .white.opacity(0.7)
            subtleFill = .white.opacity(0.45)
            rim = .black.opacity(0.06)
            controlFill = .black.opacity(0.05)
        }
    }

    /// Panes and cards.
    static let surfaceRadius: CGFloat = 16
    /// Fields, tiles and other controls that aren't capsules.
    static let controlRadius: CGFloat = 10
    /// How far a press squashes a control.
    static let pressScale: CGFloat = 0.98
    /// A short ease-out with no overshoot.
    static let motion = Animation.easeOut(duration: 0.18)
}
