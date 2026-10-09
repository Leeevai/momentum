import Foundation
import Testing
@testable import MomentumCore

@Suite("Theme palettes")
struct ThemePaletteTests {
    @Test("A file without a palette, or with one from a newer version, draws in Dusk")
    func paletteDecoding() throws {
        let missing = try FileStore.decode(Data(#"{"version": 2, "preferences": {}}"#.utf8)).preferences.palette
        let known = try FileStore.decode(Data(#"{"version": 2, "preferences": {"palette": "lagoon"}}"#.utf8)).preferences.palette
        let unknown = try FileStore.decode(Data(#"{"version": 2, "preferences": {"palette": "plaid"}}"#.utf8)).preferences.palette
        #expect(missing == .dusk)
        #expect(known == .lagoon)
        #expect(unknown == .dusk)
    }

    @Test("The palette survives a save")
    func paletteRoundTrip() throws {
        var data = AppData()
        data.preferences.palette = .midnight
        let decoded = try FileStore.decode(JSONEncoder().encode(data))
        #expect(decoded.preferences.palette == .midnight)
    }

    @Test("OKLCH converts to the sRGB glasscn publishes for the same color")
    func oklchToSRGB() {
        let white = OKLCH(1, 0, 0).sRGB
        let black = OKLCH(0, 0, 0).sRGB
        // glasscn's native tokens give Dusk's light accent, oklch(0.657 0.19 34.8), as #EE5A36.
        let coral = OKLCH(0.657, 0.19, 34.8).sRGB
        let expected = (red: 238.0 / 255, green: 90.0 / 255, blue: 54.0 / 255)
        #expect(white.red > 0.999 && white.green > 0.999 && white.blue > 0.999)
        #expect(black.red < 0.001 && black.green < 0.001 && black.blue < 0.001)
        let error = max(abs(coral.red - expected.red), abs(coral.green - expected.green), abs(coral.blue - expected.blue))
        #expect(error < 0.02)
    }

    @Test("Every palette has three aurora colors and five chart colors led by its accent, in both appearances")
    func paletteShape() {
        for palette in ThemePalette.allCases {
            for dark in [false, true] {
                let tokens = palette.tokens(dark: dark)
                let auroraCount = tokens.aurora.count
                let chartCount = tokens.chart.count
                let leadsWithAccent = tokens.chart.first == tokens.accent
                #expect(auroraCount == 3, "\(palette) aurora")
                #expect(chartCount == 5, "\(palette) chart")
                #expect(leadsWithAccent, "\(palette) chart accent")
            }
        }
    }

    @Test("Dark backgrounds are dark and light ones light, so text on glass stays legible")
    func auroraBaseContrast() {
        for palette in ThemePalette.allCases {
            let light = palette.tokens(dark: false).auroraBase.lightness
            let dark = palette.tokens(dark: true).auroraBase.lightness
            #expect(light > 0.9, "\(palette) light base")
            #expect(dark < 0.2, "\(palette) dark base")
        }
    }
}
