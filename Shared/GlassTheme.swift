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
