import Foundation
import Testing
@testable import MomentumCore

@Suite("Palette colors")
struct PaletteTests {
    /// The built-in recipes, and recipes across the range a custom palette can take.
    static let recipes: [PaletteRecipe] = {
        var recipes = ThemePalette.allCases.map(\.recipe)
        for harmony in PaletteHarmony.allCases {
            for hue in stride(from: 0.0, to: 360, by: 30) {
                for level in [0.0, 0.5, 1.0] {
                    recipes.append(PaletteRecipe(accentHue: hue, accentVividness: level, backgroundHue: hue + 90, backgroundTint: level,
                                                 harmony: harmony, swatchHue: hue, swatchVividness: 1 - level,
                                                 lightness: level, contrast: 1 - level))
                    recipes.append(PaletteRecipe(accentHue: hue + 180, accentVividness: 1, backgroundHue: hue, backgroundTint: 1,
                                                 harmony: harmony, swatchHue: hue + 15, swatchVividness: 1,
                                                 lightness: level, contrast: level))
                }
            }
        }
        return recipes
    }()

    static func everyToken() -> [(name: String, tokens: PaletteTokens)] {
        var all: [(name: String, tokens: PaletteTokens)] = []
        for (index, recipe) in recipes.enumerated() {
            let palette = Palette(id: "test-\(index)", title: "Test", recipe: recipe)
            all.append((name: "\(index) \(recipe.harmony) light", tokens: palette.light))
            all.append((name: "\(index) \(recipe.harmony) dark", tokens: palette.dark))
        }
        return all
    }

    @Test("Every color a palette draws is one sRGB can show")
    func colorsFitSRGB() {
        var outside: [String] = []
        for (name, tokens) in Self.everyToken() {
            var colors: [OKLCH] = [tokens.accent, tokens.auroraBase]
            colors += tokens.aurora
            colors += tokens.chart
            colors += tokens.swatches
            if colors.contains(where: { !$0.isInSRGB }) { outside.append(name) }
        }
        #expect(outside.isEmpty, "\(outside)")
    }

    @Test("White or black text reaches 4.5:1 on every swatch and accent, in light and dark")
    func labelsAreLegible() {
        var illegible: [String] = []
        for (name, tokens) in Self.everyToken() {
            for (index, fill) in ([tokens.accent] + tokens.swatches).enumerated() where fill.labelContrast < 4.5 {
                illegible.append("\(name) #\(index): \(fill.labelContrast)")
            }
        }
        #expect(illegible.isEmpty, "\(illegible)")
    }

    @Test("Backgrounds stay light in light mode and dark in dark mode, whatever the recipe")
    func backgroundsKeepTheirAppearance() {
        for recipe in Self.recipes {
            let palette = Palette(id: "test", title: "Test", recipe: recipe)
            let light = palette.light.auroraBase.lightness
            let dark = palette.dark.auroraBase.lightness
            #expect(light > 0.9)
            #expect(dark < 0.2)
        }
    }

    @Test("A spectrum's goal colors share one lightness and one chroma, each near its own hue")
    func spectrumIsEven() {
        for dark in [false, true] {
            let tokens = ThemePalette.slate.tokens(dark: dark)
            let colors = GoalColor.allCases.filter { $0 != .gray && $0 != .brown }
            let lightness = colors.map { tokens.swatch($0).lightness }
            let chroma = colors.map { tokens.swatch($0).chroma }
            let lightnessRange = (lightness.max() ?? 0) - (lightness.min() ?? 0)
            let chromaRange = (chroma.max() ?? 0) - (chroma.min() ?? 0)
            #expect(lightnessRange < 0.001)
            #expect(chromaRange < 0.001)
            for color in colors {
                let shift = abs(Hue.difference(tokens.swatch(color).hue, from: color.canonicalHue ?? 0))
                #expect(shift < 22, "\(color)")
            }
        }
    }

    @Test("A monochrome palette steps evenly from deepest to lightest")
    func monochromeSteps() {
        let recipe = ThemePalette.espresso.recipe
        #expect(recipe.harmony == .monochrome)
        let places = PaletteGenerator.places(for: recipe)
        let ordered = places.values.map(\.lightnessStep).sorted()
        let steps = zip(ordered, ordered.dropFirst()).map { $1 - $0 }
        let unevenness = (steps.max() ?? 0) - (steps.min() ?? 0)
        #expect(unevenness < 0.0001)
        for dark in [false, true] {
            let tokens = ThemePalette.espresso.tokens(dark: dark)
            let shades = places.sorted { $0.value.lightnessStep < $1.value.lightnessStep }.map { tokens.swatch($0.key).lightness }
            let rising = zip(shades, shades.dropFirst()).allSatisfy { $0 < $1 }
            #expect(rising)
        }
    }

    @Test("Analogous goal colors stay near the base hue")
    func analogousStaysClose() {
        let recipe = ThemePalette.fjord.recipe
        for color in GoalColor.allCases where color != .gray {
            let hue = ThemePalette.fjord.tokens(dark: false).swatch(color).hue
            let distance = abs(Hue.difference(hue, from: recipe.swatchHue))
            #expect(distance <= 50.001, "\(color)")
        }
    }

    @Test("Complementary and triadic palettes group goal colors around their anchors")
    func anchoredHarmonies() {
        for (harmony, anchors) in [(PaletteHarmony.complementary, [0.0, 180]), (.triadic, [0.0, 120, 240])] {
            var recipe = ThemePalette.slate.recipe
            recipe.harmony = harmony
            recipe.swatchHue = 200
            let places = PaletteGenerator.places(for: recipe)
            for (color, place) in places {
                let offset = Hue.difference(place.hue, from: recipe.swatchHue)
                let nearest = anchors.map { abs(Hue.difference(offset, from: $0)) }.min() ?? 360
                #expect(nearest <= 32.001, "\(harmony) \(color)")
            }
        }
    }

    @Test("Every goal color has a swatch of its own in every built-in palette")
    func swatchesAreDistinct() {
        for palette in ThemePalette.allCases {
            for dark in [false, true] {
                let swatches = palette.tokens(dark: dark).swatches
                let unique = Set(swatches.map { "\(($0.lightness * 1000).rounded()) \(($0.chroma * 1000).rounded()) \(($0.hue).rounded())" })
                #expect(unique.count == swatches.count, "\(palette) \(dark ? "dark" : "light")")
            }
        }
    }

    @Test("A goal's swatch is the one at its color's place")
    func swatchLookup() {
        let tokens = ThemePalette.dusk.tokens(dark: false)
        for (index, color) in GoalColor.allCases.enumerated() {
            let swatch = tokens.swatch(color)
            #expect(swatch == tokens.swatches[index])
        }
    }

    @Test("OKLCH contrast follows WCAG: 21:1 for black on white, 1:1 for a color on itself")
    func contrastRatio() {
        let white = OKLCH(1, 0, 0)
        let black = OKLCH(0, 0, 0)
        let blackOnWhite = black.contrast(with: white)
        let sameColor = OKLCH(0.6, 0.1, 200).contrast(with: OKLCH(0.6, 0.1, 200))
        #expect(abs(blackOnWhite - 21) < 0.01)
        #expect(abs(sameColor - 1) < 0.0001)
        #expect(OKLCH(0.9, 0.05, 90).prefersDarkLabel)
        #expect(!OKLCH(0.4, 0.1, 250).prefersDarkLabel)
    }

    @Test("Mapping into sRGB keeps lightness and hue and lowers chroma")
    func gamutMapping() {
        let vivid = OKLCH(0.9, 0.3, 260)
        let mapped = vivid.inSRGB
        #expect(!vivid.isInSRGB)
        #expect(mapped.isInSRGB)
        #expect(mapped.lightness == vivid.lightness)
        #expect(mapped.hue == vivid.hue)
        #expect(mapped.chroma < vivid.chroma)
    }
}
