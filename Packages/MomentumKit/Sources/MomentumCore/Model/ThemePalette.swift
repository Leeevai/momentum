import Foundation

/// One appearance of a palette: the accent, the aurora behind every screen (a base and three
/// drifting colors), and five chart colors, the first being the accent.
public struct PaletteTokens: Hashable, Sendable {
    public var accent: OKLCH
    public var auroraBase: OKLCH
    public var aurora: [OKLCH]
    public var chart: [OKLCH]
}

/// The app's color palettes, after glasscn's themes (https://glasscn.app, MIT license,
/// copyright 2026 Tim Mikeladze). Each has a light and a dark appearance.
public enum ThemePalette: String, Codable, CaseIterable, Sendable, Identifiable {
    case dusk, ocean, rose, sage, amber, graphite, lavender, mint, cherry, lagoon, sand, midnight

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    public var summary: String {
        switch self {
        case .dusk: "Coral over violet and peach"
        case .ocean: "Blue, teal and periwinkle"
        case .rose: "Pink over lilac"
        case .sage: "Green, lime and sea glass"
        case .amber: "Honey, apricot and lemon"
        case .graphite: "Ink on frost"
        case .lavender: "Soft violet with lilac and periwinkle"
        case .mint: "Fresh green against blue sky"
        case .cherry: "Red with a cool complement"
        case .lagoon: "Teal, aqua and deep blue"
        case .sand: "Warm neutrals, barely tinted"
        case .midnight: "Indigo, magenta and cyan"
        }
    }

    public func tokens(dark: Bool) -> PaletteTokens {
        dark ? table.dark : table.light
    }

    // Generated from glasscn's theme registry (glasscn.app/r/theme-*.json).
    private var table: (light: PaletteTokens, dark: PaletteTokens) {
        switch self {
        case .dusk:
            (light: PaletteTokens(accent: OKLCH(0.657, 0.19, 34.8), auroraBase: OKLCH(0.955, 0.007, 268.5),
                                  aurora: [OKLCH(0.829, 0.098, 37.8), OKLCH(0.809, 0.109, 296.4), OKLCH(0.907, 0.07, 70.2)],
                                  chart: [OKLCH(0.657, 0.19, 34.8), OKLCH(0.685, 0.189, 296.4), OKLCH(0.803, 0.159, 69.8), OKLCH(0.55, 0.128, 95), OKLCH(0.85, 0.096, 335)]),
             dark: PaletteTokens(accent: OKLCH(0.728, 0.171, 36.5), auroraBase: OKLCH(0.116, 0.006, 285.4),
                                  aurora: [OKLCH(0.48, 0.132, 31.7), OKLCH(0.401, 0.159, 289.2), OKLCH(0.456, 0.088, 60.9)],
                                  chart: [OKLCH(0.728, 0.171, 36.5), OKLCH(0.685, 0.189, 296.4), OKLCH(0.803, 0.159, 69.8), OKLCH(0.66, 0.128, 95), OKLCH(0.86, 0.096, 335)]))
        case .ocean:
            (light: PaletteTokens(accent: OKLCH(0.583, 0.203, 259), auroraBase: OKLCH(0.955, 0.007, 268.5),
                                  aurora: [OKLCH(0.817, 0.093, 256.2), OKLCH(0.899, 0.073, 185.2), OKLCH(0.828, 0.094, 291.7)],
                                  chart: [OKLCH(0.583, 0.203, 259), OKLCH(0.773, 0.127, 186.5), OKLCH(0.665, 0.187, 286.4), OKLCH(0.55, 0.128, 319), OKLCH(0.85, 0.096, 199)]),
             dark: PaletteTokens(accent: OKLCH(0.705, 0.159, 252.4), auroraBase: OKLCH(0.116, 0.006, 285.4),
                                  aurora: [OKLCH(0.389, 0.133, 260.3), OKLCH(0.442, 0.071, 205.5), OKLCH(0.36, 0.154, 280)],
                                  chart: [OKLCH(0.705, 0.159, 252.4), OKLCH(0.773, 0.127, 186.5), OKLCH(0.665, 0.187, 286.4), OKLCH(0.66, 0.128, 319), OKLCH(0.86, 0.096, 199)]))
        case .rose:
            (light: PaletteTokens(accent: OKLCH(0.618, 0.194, 9.9), auroraBase: OKLCH(0.955, 0.007, 268.5),
                                  aurora: [OKLCH(0.844, 0.092, 1.1), OKLCH(0.843, 0.106, 311.1), OKLCH(0.907, 0.051, 1.4)],
                                  chart: [OKLCH(0.618, 0.194, 9.9), OKLCH(0.698, 0.191, 302), OKLCH(0.771, 0.143, 43.5), OKLCH(0.55, 0.128, 70), OKLCH(0.85, 0.096, 310)]),
             dark: PaletteTokens(accent: OKLCH(0.719, 0.182, 8.2), auroraBase: OKLCH(0.116, 0.006, 285.4),
                                  aurora: [OKLCH(0.431, 0.14, 4.8), OKLCH(0.407, 0.146, 306.5), OKLCH(0.339, 0.122, 309.2)],
                                  chart: [OKLCH(0.719, 0.182, 8.2), OKLCH(0.698, 0.191, 302), OKLCH(0.771, 0.143, 43.5), OKLCH(0.66, 0.128, 70), OKLCH(0.86, 0.096, 310)]))
        case .sage:
            (light: PaletteTokens(accent: OKLCH(0.589, 0.126, 157.8), auroraBase: OKLCH(0.955, 0.007, 268.5),
                                  aurora: [OKLCH(0.89, 0.071, 160.3), OKLCH(0.927, 0.098, 121.8), OKLCH(0.87, 0.057, 211.5)],
                                  chart: [OKLCH(0.589, 0.126, 157.8), OKLCH(0.779, 0.178, 129), OKLCH(0.711, 0.118, 221.5), OKLCH(0.55, 0.128, 218), OKLCH(0.85, 0.096, 98)]),
             dark: PaletteTokens(accent: OKLCH(0.769, 0.149, 158.2), auroraBase: OKLCH(0.116, 0.006, 285.4),
                                  aurora: [OKLCH(0.456, 0.091, 159.1), OKLCH(0.47, 0.105, 130.5), OKLCH(0.432, 0.068, 211.9)],
                                  chart: [OKLCH(0.769, 0.149, 158.2), OKLCH(0.779, 0.178, 129), OKLCH(0.711, 0.118, 221.5), OKLCH(0.66, 0.128, 218), OKLCH(0.86, 0.096, 98)]))
        case .amber:
            (light: PaletteTokens(accent: OKLCH(0.65, 0.144, 65.8), auroraBase: OKLCH(0.955, 0.007, 268.5),
                                  aurora: [OKLCH(0.901, 0.092, 79.5), OKLCH(0.849, 0.086, 40.3), OKLCH(0.953, 0.079, 95.9)],
                                  chart: [OKLCH(0.65, 0.144, 65.8), OKLCH(0.712, 0.183, 34), OKLCH(0.823, 0.164, 94.1), OKLCH(0.55, 0.128, 126), OKLCH(0.85, 0.096, 6)]),
             dark: PaletteTokens(accent: OKLCH(0.82, 0.152, 73.2), auroraBase: OKLCH(0.116, 0.006, 285.4),
                                  aurora: [OKLCH(0.471, 0.094, 74), OKLCH(0.414, 0.106, 35.8), OKLCH(0.448, 0.085, 102.3)],
                                  chart: [OKLCH(0.82, 0.152, 73.2), OKLCH(0.712, 0.183, 34), OKLCH(0.823, 0.164, 94.1), OKLCH(0.66, 0.128, 126), OKLCH(0.86, 0.096, 6)]))
        case .graphite:
            (light: PaletteTokens(accent: OKLCH(0.227, 0.004, 286.1), auroraBase: OKLCH(0.955, 0.007, 268.5),
                                  aurora: [OKLCH(0.881, 0.015, 264.5), OKLCH(0.911, 0.025, 301.1), OKLCH(0.892, 0.024, 227.8)],
                                  chart: [OKLCH(0.227, 0.004, 286.1), OKLCH(0.589, 0.012, 286), OKLCH(0.753, 0.008, 286.2), OKLCH(0.55, 0.016, 346), OKLCH(0.85, 0.012, 226)]),
             dark: PaletteTokens(accent: OKLCH(0.963, 0.007, 286.3), auroraBase: OKLCH(0.116, 0.006, 285.4),
                                  aurora: [OKLCH(0.326, 0.02, 269.5), OKLCH(0.339, 0.032, 300), OKLCH(0.315, 0.028, 236.2)],
                                  chart: [OKLCH(0.963, 0.007, 286.3), OKLCH(0.589, 0.012, 286), OKLCH(0.753, 0.008, 286.2), OKLCH(0.66, 0.016, 346), OKLCH(0.86, 0.012, 226)]))
        case .lavender:
            (light: PaletteTokens(accent: OKLCH(0.6, 0.15, 300), auroraBase: OKLCH(0.955, 0.012, 300),
                                  aurora: [OKLCH(0.84, 0.083, 300), OKLCH(0.83, 0.09, 338), OKLCH(0.9, 0.063, 266)],
                                  chart: [OKLCH(0.6, 0.15, 300), OKLCH(0.66, 0.15, 338), OKLCH(0.78, 0.128, 266), OKLCH(0.55, 0.12, 0), OKLCH(0.85, 0.09, 240)]),
             dark: PaletteTokens(accent: OKLCH(0.74, 0.138, 300), auroraBase: OKLCH(0.12, 0.012, 300),
                                  aurora: [OKLCH(0.44, 0.117, 300), OKLCH(0.38, 0.135, 338), OKLCH(0.42, 0.09, 266)],
                                  chart: [OKLCH(0.74, 0.138, 300), OKLCH(0.72, 0.15, 338), OKLCH(0.82, 0.128, 266), OKLCH(0.66, 0.12, 0), OKLCH(0.86, 0.09, 240)]))
        case .mint:
            (light: PaletteTokens(accent: OKLCH(0.6, 0.13, 165), auroraBase: OKLCH(0.955, 0.012, 165),
                                  aurora: [OKLCH(0.84, 0.072, 165), OKLCH(0.83, 0.078, 315), OKLCH(0.9, 0.055, 15)],
                                  chart: [OKLCH(0.6, 0.13, 165), OKLCH(0.66, 0.13, 315), OKLCH(0.78, 0.111, 15), OKLCH(0.55, 0.104, 225), OKLCH(0.85, 0.078, 105)]),
             dark: PaletteTokens(accent: OKLCH(0.74, 0.12, 165), auroraBase: OKLCH(0.12, 0.012, 165),
                                  aurora: [OKLCH(0.44, 0.101, 165), OKLCH(0.38, 0.117, 315), OKLCH(0.42, 0.078, 15)],
                                  chart: [OKLCH(0.74, 0.12, 165), OKLCH(0.72, 0.13, 315), OKLCH(0.82, 0.111, 15), OKLCH(0.66, 0.104, 225), OKLCH(0.86, 0.078, 105)]))
        case .cherry:
            (light: PaletteTokens(accent: OKLCH(0.6, 0.2, 22), auroraBase: OKLCH(0.955, 0.012, 22),
                                  aurora: [OKLCH(0.84, 0.11, 22), OKLCH(0.83, 0.12, 202), OKLCH(0.9, 0.084, 46)],
                                  chart: [OKLCH(0.6, 0.2, 22), OKLCH(0.66, 0.2, 202), OKLCH(0.78, 0.17, 46), OKLCH(0.55, 0.16, 82), OKLCH(0.85, 0.12, 322)]),
             dark: PaletteTokens(accent: OKLCH(0.74, 0.184, 22), auroraBase: OKLCH(0.12, 0.012, 22),
                                  aurora: [OKLCH(0.44, 0.156, 22), OKLCH(0.38, 0.18, 202), OKLCH(0.42, 0.12, 46)],
                                  chart: [OKLCH(0.74, 0.184, 22), OKLCH(0.72, 0.2, 202), OKLCH(0.82, 0.17, 46), OKLCH(0.66, 0.16, 82), OKLCH(0.86, 0.12, 322)]))
        case .lagoon:
            (light: PaletteTokens(accent: OKLCH(0.6, 0.14, 200), auroraBase: OKLCH(0.955, 0.012, 200),
                                  aurora: [OKLCH(0.84, 0.077, 200), OKLCH(0.83, 0.084, 238), OKLCH(0.9, 0.059, 166)],
                                  chart: [OKLCH(0.6, 0.14, 200), OKLCH(0.66, 0.14, 238), OKLCH(0.78, 0.119, 166), OKLCH(0.55, 0.112, 260), OKLCH(0.85, 0.084, 140)]),
             dark: PaletteTokens(accent: OKLCH(0.74, 0.129, 200), auroraBase: OKLCH(0.12, 0.012, 200),
                                  aurora: [OKLCH(0.44, 0.109, 200), OKLCH(0.38, 0.126, 238), OKLCH(0.42, 0.084, 166)],
                                  chart: [OKLCH(0.74, 0.129, 200), OKLCH(0.72, 0.14, 238), OKLCH(0.82, 0.119, 166), OKLCH(0.66, 0.112, 260), OKLCH(0.86, 0.084, 140)]))
        case .sand:
            (light: PaletteTokens(accent: OKLCH(0.6, 0.07, 70), auroraBase: OKLCH(0.955, 0.012, 70),
                                  aurora: [OKLCH(0.8, 0.039, 70), OKLCH(0.88, 0.042, 78), OKLCH(0.92, 0.029, 62)],
                                  chart: [OKLCH(0.6, 0.07, 70), OKLCH(0.66, 0.07, 78), OKLCH(0.78, 0.06, 62), OKLCH(0.55, 0.056, 130), OKLCH(0.85, 0.042, 10)]),
             dark: PaletteTokens(accent: OKLCH(0.74, 0.064, 70), auroraBase: OKLCH(0.12, 0.012, 70),
                                  aurora: [OKLCH(0.44, 0.055, 70), OKLCH(0.38, 0.063, 78), OKLCH(0.42, 0.042, 62)],
                                  chart: [OKLCH(0.74, 0.064, 70), OKLCH(0.72, 0.07, 78), OKLCH(0.82, 0.06, 62), OKLCH(0.66, 0.056, 130), OKLCH(0.86, 0.042, 10)]))
        case .midnight:
            (light: PaletteTokens(accent: OKLCH(0.6, 0.19, 275), auroraBase: OKLCH(0.955, 0.012, 275),
                                  aurora: [OKLCH(0.84, 0.105, 275), OKLCH(0.83, 0.114, 35), OKLCH(0.9, 0.08, 155)],
                                  chart: [OKLCH(0.6, 0.19, 275), OKLCH(0.66, 0.19, 35), OKLCH(0.78, 0.162, 155), OKLCH(0.55, 0.152, 335), OKLCH(0.85, 0.114, 215)]),
             dark: PaletteTokens(accent: OKLCH(0.74, 0.175, 275), auroraBase: OKLCH(0.12, 0.012, 275),
                                  aurora: [OKLCH(0.44, 0.148, 275), OKLCH(0.38, 0.171, 35), OKLCH(0.42, 0.114, 155)],
                                  chart: [OKLCH(0.74, 0.175, 275), OKLCH(0.72, 0.19, 35), OKLCH(0.82, 0.162, 155), OKLCH(0.66, 0.152, 335), OKLCH(0.86, 0.114, 215)]))
        }
    }
}
