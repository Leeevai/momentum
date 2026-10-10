import Foundation

/// One appearance of a palette: the accent, the aurora behind every screen (a base and three
/// drifting colors), five chart colors led by the accent, and a swatch for every goal color.
public struct PaletteTokens: Hashable, Sendable {
    public var accent: OKLCH
    public var auroraBase: OKLCH
    public var aurora: [OKLCH]
    public var chart: [OKLCH]
    /// One per `GoalColor`, in `GoalColor.allCases` order.
    public var swatches: [OKLCH]

    /// The palette's color for a goal of `color`.
    public func swatch(_ color: GoalColor) -> OKLCH {
        swatches[color.index]
    }
}

/// What text in a palette's colors sits on, and has to read against. In the apps it's a glass
/// pane over the aurora: in light mode white at 52% over a blob of lightness 0.84, in dark a dark
/// tint at 45% over one of 0.44. Widgets have no panes, so their text sits on the aurora itself.
/// Each is taken at the strongest blob, rounded toward the harder case.
public enum TextSurface: Sendable {
    case glass
    case aurora

    /// WCAG luminance of the surface in each appearance.
    public func luminance(dark: Bool) -> Double {
        switch self {
        case .glass: dark ? 0.06 : 0.75
        case .aurora: dark ? 0.09 : 0.59
        }
    }
}

/// A palette ready to draw: what it's called, and its colors in light and dark.
public struct Palette: Hashable, Sendable, Identifiable {
    /// The built-in palette's name, or `custom-` and the custom palette's id.
    public let id: String
    public let title: String
    public let light: PaletteTokens
    public let dark: PaletteTokens

    public init(id: String, title: String, recipe: PaletteRecipe) {
        self.id = id
        self.title = title
        light = PaletteGenerator.tokens(for: recipe, dark: false)
        dark = PaletteGenerator.tokens(for: recipe, dark: true)
    }

    public init(_ palette: ThemePalette) {
        self = Self.builtIn[palette] ?? Palette(id: palette.rawValue, title: palette.title, recipe: palette.recipe)
    }

    public init(_ palette: CustomPalette) {
        self.init(id: "custom-\(palette.id.uuidString)", title: palette.displayName, recipe: palette.recipe)
    }

    public func tokens(dark: Bool) -> PaletteTokens {
        dark ? self.dark : light
    }

    /// The default palette.
    public static var standard: Palette { Palette(.standard) }

    /// The built-in palettes, generated once.
    private static let builtIn: [ThemePalette: Palette] = Dictionary(uniqueKeysWithValues: ThemePalette.allCases.map {
        ($0, Palette(id: $0.rawValue, title: $0.title, recipe: $0.recipe))
    })
}

/// How a palette spreads goal colors around its base hue.
public enum PaletteHarmony: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Every hue, muted alike: goal colors as unlike each other as a palette allows.
    case spectrum
    /// Neighbors of the base hue, in alternating lighter and deeper shades.
    case analogous
    /// The base hue and its opposite.
    case complementary
    /// Three hues a third of the wheel apart.
    case triadic
    /// The base hue alone, in even steps of lightness.
    case monochrome

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    public var summary: String {
        switch self {
        case .spectrum: "Every hue, muted alike"
        case .analogous: "Neighbors of the base hue"
        case .complementary: "The base hue and its opposite"
        case .triadic: "Three hues evenly apart"
        case .monochrome: "One hue, lighter to deeper"
        }
    }
}

/// What a palette is made from: an accent, a background tint, goal colors in a harmony around a
/// base hue, and a feel for lightness and contrast. Built-in and custom palettes both come from
/// one, so every palette is drawn by the same rules.
public struct PaletteRecipe: Codable, Hashable, Sendable {
    /// The accent's hue, in degrees.
    public var accentHue: Double
    /// From 0, a neutral accent (ink in light mode, paper in dark), to 1, the most vivid.
    public var accentVividness: Double
    /// The hue the aurora behind every screen is tinted with.
    public var backgroundHue: Double
    /// From 0, a nearly neutral background, to 1, a strongly tinted one.
    public var backgroundTint: Double
    /// How goal colors spread around `swatchHue`.
    public var harmony: PaletteHarmony
    /// The hue goal colors are built around.
    public var swatchHue: Double
    /// From 0, goal colors that are nearly gray, to 1, the most vivid.
    public var swatchVividness: Double
    /// From 0, deeper colors, to 1, lighter ones.
    public var lightness: Double
    /// From 0, soft (colors close together, a faint aurora), to 1, crisp.
    public var contrast: Double

    public init(accentHue: Double, accentVividness: Double, backgroundHue: Double, backgroundTint: Double, harmony: PaletteHarmony,
                swatchHue: Double, swatchVividness: Double, lightness: Double = 0.5, contrast: Double = 0.5) {
        self.accentHue = Hue.normalized(accentHue)
        self.accentVividness = Self.unit(accentVividness)
        self.backgroundHue = Hue.normalized(backgroundHue)
        self.backgroundTint = Self.unit(backgroundTint)
        self.harmony = harmony
        self.swatchHue = Hue.normalized(swatchHue)
        self.swatchVividness = Self.unit(swatchVividness)
        self.lightness = Self.unit(lightness)
        self.contrast = Self.unit(contrast)
    }

    /// The default palette's recipe: what a damaged or missing value falls back to.
    public static var standard: PaletteRecipe { ThemePalette.standard.recipe }

    private enum CodingKeys: String, CodingKey {
        case accentHue, accentVividness, backgroundHue, backgroundTint, harmony, swatchHue, swatchVividness, lightness, contrast
    }

    /// Every value decodes on its own: one that's missing, out of range or not a number falls
    /// back to the default palette's, and a harmony from a newer version draws as a spectrum.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.standard
        func value(_ key: CodingKeys, _ defaultValue: Double) -> Double {
            guard let number = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil, number.isFinite else { return defaultValue }
            return number
        }
        self.init(accentHue: value(.accentHue, fallback.accentHue),
                  accentVividness: value(.accentVividness, fallback.accentVividness),
                  backgroundHue: value(.backgroundHue, fallback.backgroundHue),
                  backgroundTint: value(.backgroundTint, fallback.backgroundTint),
                  harmony: ((try? c.decodeIfPresent(PaletteHarmony.self, forKey: .harmony)) ?? nil) ?? .spectrum,
                  swatchHue: value(.swatchHue, fallback.swatchHue),
                  swatchVividness: value(.swatchVividness, fallback.swatchVividness),
                  lightness: value(.lightness, fallback.lightness),
                  contrast: value(.contrast, fallback.contrast))
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0.5
    }
}

/// A palette someone made in Settings: a name and a recipe.
public struct CustomPalette: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var recipe: PaletteRecipe

    public init(id: UUID = UUID(), name: String, recipe: PaletteRecipe) {
        self.id = id
        self.name = name
        self.recipe = recipe
    }

    /// The name, or "Custom" when it's blank.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Custom" : trimmed
    }

    private enum CodingKeys: String, CodingKey { case id, name, recipe }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decode(.name, default: "")) ?? ""
        recipe = (try? c.decode(.recipe, default: PaletteRecipe.standard)) ?? .standard
    }
}

extension GoalColor {
    /// The color's place in `GoalColor.allCases`, and so in a palette's swatches.
    var index: Int {
        switch self {
        case .blue: 0
        case .indigo: 1
        case .purple: 2
        case .pink: 3
        case .red: 4
        case .orange: 5
        case .yellow: 6
        case .green: 7
        case .mint: 8
        case .teal: 9
        case .cyan: 10
        case .brown: 11
        case .gray: 12
        }
    }

    /// Where the color sits on the wheel before a palette moves it, in OKLCH degrees, spaced so
    /// that neighbors stay apart once muted; nil for gray, which has no hue.
    var canonicalHue: Double? {
        switch self {
        case .red: 25
        case .orange: 55
        case .brown: 62
        case .yellow: 90
        case .green: 140
        case .mint: 170
        case .teal: 195
        case .cyan: 220
        case .blue: 250
        case .indigo: 280
        case .purple: 310
        case .pink: 345
        case .gray: nil
        }
    }
}

/// Turns a recipe into colors. Every color is kept inside sRGB by lowering its chroma, and white
/// or black text reaches 4.5:1 on every accent and swatch.
enum PaletteGenerator {
    static func tokens(for recipe: PaletteRecipe, dark: Bool) -> PaletteTokens {
        let accentColor = Self.accent(for: recipe, dark: dark)
        let layout = Self.places(for: recipe)
        let swatches = GoalColor.allCases.map { Self.swatch($0, at: layout[$0], for: recipe, dark: dark) }
        let background = Self.aurora(for: recipe, dark: dark)
        return PaletteTokens(accent: accentColor, auroraBase: background.base, aurora: background.blobs,
                             chart: Self.chart(accent: accentColor, swatches: swatches), swatches: swatches)
    }

    private static func accent(for recipe: PaletteRecipe, dark: Bool) -> OKLCH {
        let lightness = recipe.lightness - 0.5
        let contrast = recipe.contrast - 0.5
        var chroma = 0.2 * recipe.accentVividness
        // An accent with next to no color has to stand apart by lightness: ink, or paper.
        let neutral = min(1, max(0, 1 - chroma / 0.04))
        var level: Double
        if dark {
            level = 0.74 + 0.08 * contrast + 0.12 * lightness
            level += (0.93 - level) * neutral
            chroma *= 0.92
        } else {
            level = 0.575 - 0.08 * contrast + 0.16 * lightness
            level += (0.26 - level) * neutral
        }
        // The system draws the accent as text too (buttons, links), so it has to read on glass.
        return OKLCH(level, chroma, recipe.accentHue).inSRGB.readable(onLuminance: TextSurface.glass.luminance(dark: dark)).legible()
    }

    /// The aurora's base and its three blobs: the background hue, the accent's, and the
    /// background turned away from the accent.
    private static func aurora(for recipe: PaletteRecipe, dark: Bool) -> (base: OKLCH, blobs: [OKLCH]) {
        let lightness = recipe.lightness - 0.5
        let contrast = recipe.contrast - 0.5
        let tint = 0.01 + 0.16 * recipe.backgroundTint
        let strength = 0.75 + 0.5 * recipe.contrast
        let background = recipe.backgroundHue
        let side: Double = Hue.difference(background, from: recipe.accentHue) >= 0 ? 1 : -1
        let hues = [background, recipe.accentHue, Hue.normalized(background + 40 * side)]
        let baseChroma = min(0.014, 0.004 + tint * 0.12)
        if dark {
            let base = OKLCH(0.125 + 0.04 * lightness - 0.02 * contrast, baseChroma, background).inSRGB
            return (base, [OKLCH(0.44, 0.78 * tint * strength, hues[0]).inSRGB,
                           OKLCH(0.38, 0.9 * tint * strength, hues[1]).inSRGB,
                           OKLCH(0.42, 0.6 * tint * strength, hues[2]).inSRGB])
        }
        let base = OKLCH(0.955 + 0.02 * lightness, baseChroma, background).inSRGB
        return (base, [OKLCH(0.85, 0.55 * tint * strength, hues[0]).inSRGB,
                       OKLCH(0.84, 0.6 * tint * strength, hues[1]).inSRGB,
                       OKLCH(0.91, 0.42 * tint * strength, hues[2]).inSRGB])
    }

    private static func swatch(_ color: GoalColor, at place: Place?, for recipe: PaletteRecipe, dark: Bool) -> OKLCH {
        let base = dark ? 0.735 + 0.12 * (recipe.lightness - 0.5) : 0.525 + 0.16 * (recipe.lightness - 0.5)
        let chroma = 0.02 + 0.15 * recipe.swatchVividness
        guard let place else {
            // Gray: the palette's neutral, faintly tinted with its base hue.
            return OKLCH(base, min(0.02, 0.004 + chroma * 0.12), recipe.swatchHue).inSRGB.legible()
        }
        let spread = 0.015 + 0.07 * recipe.contrast
        var lightness = base + place.lightnessStep * spread
        var scaledChroma = chroma * place.chromaScale
        if color == .brown && recipe.harmony != .monochrome {
            // Earthy: deeper and duller than the orange beside it. In one hue it's simply a step.
            lightness -= 0.07
            scaledChroma *= 0.55
        }
        return OKLCH(lightness, scaledChroma, place.hue).inSRGB.legible()
    }

    /// Where a goal color lands in the recipe's harmony: its hue, how many spreads its lightness
    /// moves from the palette's, and how its chroma scales.
    struct Place: Equatable {
        var hue: Double
        var lightnessStep: Double
        var chromaScale: Double
    }

    static func places(for recipe: PaletteRecipe) -> [GoalColor: Place] {
        let base = recipe.swatchHue
        func offset(_ color: GoalColor) -> Double { Hue.difference(color.canonicalHue ?? base, from: base) }
        // The colors with a hue, from furthest one way round the wheel to furthest the other.
        let ranked = GoalColor.allCases.filter { $0.canonicalHue != nil }.sorted { offset($0) < offset($1) }
        let last = Double(ranked.count - 1)
        var places: [GoalColor: Place] = [:]
        switch recipe.harmony {
        case .spectrum:
            // Each hue turns a little toward the base, never far enough to pass for its neighbor.
            for color in ranked {
                places[color] = Place(hue: Hue.normalized(base + offset(color) * 0.94), lightnessStep: 0, chromaScale: 1)
            }
        case .analogous:
            for (rank, color) in ranked.enumerated() {
                let position = Double(rank) / last * 2 - 1
                places[color] = Place(hue: Hue.normalized(base + 50 * position), lightnessStep: rank.isMultiple(of: 2) ? 1 : -1, chromaScale: 1)
            }
        case .monochrome:
            for (rank, color) in ranked.enumerated() {
                let position = Double(rank) / last * 2 - 1
                places[color] = Place(hue: Hue.normalized(base + 8 * position), lightnessStep: 1.6 * position,
                                      chromaScale: 0.7 + 0.5 * (1 - abs(position)))
            }
        case .complementary, .triadic:
            let anchors: [Double] = recipe.harmony == .complementary ? [0, 180] : [0, 120, 240]
            let spread: Double = recipe.harmony == .complementary ? 32 : 24
            for anchor in anchors {
                let members = ranked
                    .filter { nearest(to: offset($0), among: anchors) == anchor }
                    .sorted { Hue.difference(offset($0), from: anchor) < Hue.difference(offset($1), from: anchor) }
                for (rank, color) in members.enumerated() {
                    let position = members.count == 1 ? 0 : Double(rank) / Double(members.count - 1) * 2 - 1
                    places[color] = Place(hue: Hue.normalized(base + anchor + spread * position),
                                          lightnessStep: rank.isMultiple(of: 2) ? 1 : -1, chromaScale: 1)
                }
            }
        }
        return places
    }

    /// The anchor `offset` is closest to, the first of them on a tie.
    private static func nearest(to offset: Double, among anchors: [Double]) -> Double {
        var best = anchors[0]
        for anchor in anchors.dropFirst() where abs(Hue.difference(offset, from: anchor)) < abs(Hue.difference(offset, from: best)) {
            best = anchor
        }
        return best
    }

    /// The accent, then the four swatches furthest from it and from each other, so a chart's
    /// series stay apart in any harmony.
    private static func chart(accent: OKLCH, swatches: [OKLCH]) -> [OKLCH] {
        var candidates = GoalColor.allCases.filter { $0 != .gray && $0 != .brown }.map { swatches[$0.index] }
        var picked = [accent]
        while picked.count < 5, !candidates.isEmpty {
            let distances = candidates.map { candidate in picked.map { distance(candidate, $0) }.min() ?? 0 }
            guard let best = distances.indices.max(by: { distances[$0] < distances[$1] }) else { break }
            picked.append(candidates.remove(at: best))
        }
        return picked
    }

    /// Euclidean distance in OKLab, where equal distances look about equally different.
    private static func distance(_ first: OKLCH, _ second: OKLCH) -> Double {
        let firstAngle = first.hue * .pi / 180
        let secondAngle = second.hue * .pi / 180
        let lightness = first.lightness - second.lightness
        let a = first.chroma * cos(firstAngle) - second.chroma * cos(secondAngle)
        let b = first.chroma * sin(firstAngle) - second.chroma * sin(secondAngle)
        return (lightness * lightness + a * a + b * b).squareRoot()
    }
}
