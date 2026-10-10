import Foundation

/// The built-in palettes: calm ones, after glasscn's themes (https://glasscn.app, MIT license,
/// copyright 2026 Tim Mikeladze), each generated from a recipe in light and dark. Earlier
/// versions had louder palettes; a file that names one of those opens in the closest of these.
public enum ThemePalette: String, CaseIterable, Sendable, Identifiable {
    case slate, graphite, fjord, sage, forest, sand, clay, espresso, dusk, rose

    /// The palette a new install, or a file without one, draws in.
    public static let standard: ThemePalette = .slate

    /// The palette a saved name stands for: its own, or the closest one for a palette earlier
    /// versions had.
    public init?(stored name: String) {
        if let palette = ThemePalette(rawValue: name) {
            self = palette
            return
        }
        switch name {
        case "ocean", "lagoon": self = .fjord
        case "amber": self = .sand
        case "lavender": self = .dusk
        case "mint": self = .sage
        case "cherry": self = .clay
        case "midnight": self = .slate
        default: return nil
        }
    }

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    public var summary: String {
        switch self {
        case .slate: "Blue-gray and calm, every color muted"
        case .graphite: "Ink on frost, colors barely there"
        case .fjord: "Glacier blues and deep teal"
        case .sage: "Soft greens and sea glass"
        case .forest: "Pine, moss and lichen"
        case .sand: "Warm neutrals, barely tinted"
        case .clay: "Terracotta, ochre and stone"
        case .espresso: "Coffee, cream and cocoa"
        case .dusk: "Muted coral over dusty violet"
        case .rose: "Dusty rose, blush and peach"
        }
    }

    public var recipe: PaletteRecipe {
        switch self {
        case .slate:
            PaletteRecipe(accentHue: 252, accentVividness: 0.42, backgroundHue: 250, backgroundTint: 0.32, harmony: .spectrum,
                          swatchHue: 250, swatchVividness: 0.42, lightness: 0.5, contrast: 0.45)
        case .graphite:
            PaletteRecipe(accentHue: 270, accentVividness: 0, backgroundHue: 270, backgroundTint: 0.1, harmony: .spectrum,
                          swatchHue: 270, swatchVividness: 0.18, lightness: 0.5, contrast: 0.55)
        case .fjord:
            PaletteRecipe(accentHue: 222, accentVividness: 0.5, backgroundHue: 210, backgroundTint: 0.45, harmony: .analogous,
                          swatchHue: 215, swatchVividness: 0.5, lightness: 0.5, contrast: 0.5)
        case .sage:
            PaletteRecipe(accentHue: 155, accentVividness: 0.4, backgroundHue: 150, backgroundTint: 0.4, harmony: .analogous,
                          swatchHue: 150, swatchVividness: 0.45, lightness: 0.55, contrast: 0.45)
        case .forest:
            PaletteRecipe(accentHue: 160, accentVividness: 0.45, backgroundHue: 150, backgroundTint: 0.4, harmony: .analogous,
                          swatchHue: 135, swatchVividness: 0.48, lightness: 0.3, contrast: 0.65)
        case .sand:
            PaletteRecipe(accentHue: 70, accentVividness: 0.3, backgroundHue: 75, backgroundTint: 0.3, harmony: .analogous,
                          swatchHue: 70, swatchVividness: 0.32, lightness: 0.55, contrast: 0.4)
        case .clay:
            PaletteRecipe(accentHue: 40, accentVividness: 0.55, backgroundHue: 55, backgroundTint: 0.4, harmony: .analogous,
                          swatchHue: 45, swatchVividness: 0.5, lightness: 0.5, contrast: 0.5)
        case .espresso:
            PaletteRecipe(accentHue: 55, accentVividness: 0.38, backgroundHue: 60, backgroundTint: 0.32, harmony: .monochrome,
                          swatchHue: 55, swatchVividness: 0.4, lightness: 0.45, contrast: 0.6)
        case .dusk:
            PaletteRecipe(accentHue: 35, accentVividness: 0.6, backgroundHue: 300, backgroundTint: 0.42, harmony: .spectrum,
                          swatchHue: 330, swatchVividness: 0.45, lightness: 0.5, contrast: 0.5)
        case .rose:
            PaletteRecipe(accentHue: 8, accentVividness: 0.48, backgroundHue: 355, backgroundTint: 0.4, harmony: .analogous,
                          swatchHue: 15, swatchVividness: 0.42, lightness: 0.55, contrast: 0.45)
        }
    }

    public func tokens(dark: Bool) -> PaletteTokens {
        Palette(self).tokens(dark: dark)
    }

    /// The built-in palette most like `recipe`, by its accent: what versions without custom
    /// palettes draw in while a custom one is in use.
    public static func nearest(to recipe: PaletteRecipe) -> ThemePalette {
        func distance(_ palette: ThemePalette) -> Double {
            let other = palette.recipe
            // Hue matters only as much as both accents have color; two neutral ones match.
            let colorful = min(1, min(recipe.accentVividness, other.accentVividness) / 0.3)
            let hue = abs(Hue.difference(recipe.accentHue, from: other.accentHue)) / 180 * colorful
            return hue + abs(recipe.accentVividness - other.accentVividness) + abs(recipe.lightness - other.lightness) * 0.3
        }
        return allCases.min { distance($0) < distance($1) } ?? .standard
    }
}

extension ThemePalette: Codable {
    /// Reads a palette's name, mapping one earlier versions had to its closest; a name this
    /// version doesn't know fails, so the caller can fall back.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let palette = ThemePalette(stored: name) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown palette \(name)")
        }
        self = palette
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
