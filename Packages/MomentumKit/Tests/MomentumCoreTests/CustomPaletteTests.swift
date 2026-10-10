import Foundation
import Testing
@testable import MomentumCore

@Suite("Custom palettes")
struct CustomPaletteTests {
    private func preferences(_ json: String) throws -> Preferences {
        try FileStore.decode(Data(#"{"version": 2, "preferences": \#(json)}"#.utf8)).preferences
    }

    @Test("A file from before custom palettes has none, and draws in its built-in palette")
    func missingFields() throws {
        let decoded = try preferences(#"{"palette": "clay"}"#)
        let active = decoded.activePalette.id
        #expect(decoded.customPalettes.isEmpty)
        #expect(decoded.customPaletteID == nil)
        #expect(active == "clay")
    }

    @Test("A custom palette and the choice of it survive a save")
    func roundTrip() throws {
        var data = AppData()
        let custom = CustomPalette(name: "Harbor", recipe: PaletteRecipe(accentHue: 200, accentVividness: 0.6, backgroundHue: 230,
                                                                           backgroundTint: 0.3, harmony: .triadic, swatchHue: 200,
                                                                           swatchVividness: 0.4, lightness: 0.7, contrast: 0.2))
        data.preferences.choose(custom)
        let decoded = try FileStore.decode(JSONEncoder().encode(data)).preferences
        let active = decoded.activePalette
        #expect(decoded.customPalettes == [custom])
        #expect(decoded.customPaletteID == custom.id)
        #expect(active == Palette(custom))
        #expect(active.title == "Harbor")
    }

    @Test("Choosing a custom palette keeps the closest built-in one for versions without custom palettes")
    func compatibilityPalette() {
        var preferences = Preferences()
        var recipe = ThemePalette.clay.recipe
        recipe.harmony = .monochrome
        recipe.contrast = 0.9
        preferences.choose(CustomPalette(name: "Kiln", recipe: recipe))
        #expect(preferences.palette == .clay)
        preferences.choose(.sage)
        #expect(preferences.customPaletteID == nil)
        #expect(preferences.activePalette == Palette(.sage))
    }

    @Test("Editing the palette in use redraws in it; deleting it falls back to the closest built-in one")
    func editAndDelete() {
        var preferences = Preferences()
        var custom = CustomPalette(name: "Moss", recipe: ThemePalette.forest.recipe)
        preferences.choose(custom)
        custom.recipe = ThemePalette.rose.recipe
        preferences.save(custom)
        #expect(preferences.customPalettes.count == 1)
        #expect(preferences.activePalette == Palette(custom))
        #expect(preferences.palette == .rose)
        preferences.deleteCustomPalette(custom.id)
        #expect(preferences.customPalettes.isEmpty)
        #expect(preferences.customPaletteID == nil)
        #expect(preferences.activePalette == Palette(.rose))
    }

    @Test("Saving a palette that isn't in use leaves the choice alone")
    func saveWithoutChoosing() {
        var preferences = Preferences()
        preferences.choose(.fjord)
        preferences.save(CustomPalette(name: "Later", recipe: ThemePalette.sand.recipe))
        #expect(preferences.customPalettes.count == 1)
        #expect(preferences.activePalette == Palette(.fjord))
    }

    @Test("A choice of a custom palette that's gone draws in the built-in one")
    func danglingChoice() throws {
        let decoded = try preferences(#"{"palette": "sand", "customPaletteID": "8E7D3C1A-0000-4000-8000-000000000001"}"#)
        let active = decoded.activePalette
        #expect(active == Palette(.sand))
    }

    @Test("A damaged custom palette is dropped, and the others kept")
    func lossyPalettes() throws {
        let decoded = try preferences(#"""
        {"customPalettes": [
            {"name": "No id"},
            {"id": "8E7D3C1A-0000-4000-8000-000000000002", "name": "Kept", "recipe": {"accentHue": 30}},
            "not a palette"
        ]}
        """#)
        let names = decoded.customPalettes.map(\.name)
        #expect(names == ["Kept"])
    }

    @Test("A recipe's missing, out-of-range or unknown values fall back, one by one")
    func recipeDecoding() throws {
        let json = #"{"accentHue": -30, "accentVividness": 4, "lightness": "high", "harmony": "plaid", "contrast": 0.25}"#
        let recipe = try JSONDecoder().decode(PaletteRecipe.self, from: Data(json.utf8))
        let standard = PaletteRecipe.standard
        #expect(recipe.accentHue == 330)
        #expect(recipe.accentVividness == 1)
        #expect(recipe.lightness == standard.lightness)
        #expect(recipe.harmony == .spectrum)
        #expect(recipe.contrast == 0.25)
        #expect(recipe.backgroundHue == standard.backgroundHue)
    }

    @Test("A custom palette without a name is called Custom")
    func blankName() {
        let palette = CustomPalette(name: "  ", recipe: .standard)
        #expect(palette.displayName == "Custom")
        #expect(Palette(palette).title == "Custom")
    }

    @Test("Custom palettes sync with the other preferences: the latest change wins")
    func syncsWithPreferences() throws {
        var phone = AppData()
        var mac = AppData()
        let custom = CustomPalette(name: "Tide", recipe: ThemePalette.fjord.recipe)
        phone.preferences.choose(custom)
        phone.sync.stamps[SyncState.preferences] = Date(timeIntervalSince1970: 2_000)
        mac.preferences.choose(.espresso)
        mac.sync.stamps[SyncState.preferences] = Date(timeIntervalSince1970: 1_000)
        let merged = SyncMerge.merge(mac, phone)
        #expect(merged.preferences.customPalettes == [custom])
        #expect(merged.preferences.activePalette == Palette(custom))
    }
}
