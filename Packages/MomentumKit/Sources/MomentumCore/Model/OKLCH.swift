import Foundation

/// A color in OKLCH: perceptual lightness from 0 to 1, chroma, and hue in degrees. The palettes
/// are defined in it, as glasscn defines them, so their colors keep even steps of lightness.
public struct OKLCH: Hashable, Sendable {
    public var lightness: Double
    public var chroma: Double
    public var hue: Double

    public init(_ lightness: Double, _ chroma: Double, _ hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    /// Gamma-encoded sRGB components from 0 to 1, clipped where the color falls outside sRGB.
    public var sRGB: (red: Double, green: Double, blue: Double) {
        let linear = linearSRGB
        return (Self.encode(linear.red), Self.encode(linear.green), Self.encode(linear.blue))
    }

    /// Linear sRGB components, unclipped: one outside 0...1 means sRGB can't show the color.
    var linearSRGB: (red: Double, green: Double, blue: Double) {
        let angle = hue * .pi / 180
        let a = chroma * cos(angle)
        let b = chroma * sin(angle)
        // OKLab to linear sRGB (Björn Ottosson's matrices).
        let l = Self.cube(lightness + 0.3963377774 * a + 0.2158037573 * b)
        let m = Self.cube(lightness - 0.1055613458 * a - 0.0638541728 * b)
        let s = Self.cube(lightness - 0.0894841775 * a - 1.2914855480 * b)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    /// Whether sRGB can show the color, give or take a rounding error.
    public var isInSRGB: Bool {
        let linear = linearSRGB
        func fits(_ value: Double) -> Bool { value >= -0.0005 && value <= 1.0005 }
        return fits(linear.red) && fits(linear.green) && fits(linear.blue)
    }

    /// The color with its chroma lowered until sRGB can show it. Clipping each channel instead
    /// would shift its hue and lightness, so a generated palette would lose its even steps.
    public var inSRGB: OKLCH {
        var color = self
        color.lightness = min(1, max(0, lightness))
        color.chroma = max(0, chroma)
        guard !color.isInSRGB else { return color }
        var low = 0.0
        var high = color.chroma
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if OKLCH(color.lightness, middle, hue).isInSRGB {
                low = middle
            } else {
                high = middle
            }
        }
        color.chroma = low
        return color
    }

    /// WCAG relative luminance, from 0 for black to 1 for white, of the color as sRGB shows it.
    public var luminance: Double {
        let linear = linearSRGB
        func clipped(_ value: Double) -> Double { min(1, max(0, value)) }
        return 0.2126 * clipped(linear.red) + 0.7152 * clipped(linear.green) + 0.0722 * clipped(linear.blue)
    }

    /// The WCAG contrast ratio with `other`, from 1 to 21.
    public func contrast(with other: OKLCH) -> Double {
        Self.contrast(luminance, other.luminance)
    }

    // MARK: - Labels on fills

    /// Labels on fills are white or black: between them, one reaches 4.5:1 on any fill. A gray
    /// in place of black would leave fills of middle lightness where neither does.
    static let lightLabelLuminance = 1.0
    static let darkLabelLuminance = 0.0

    /// Whether a label on a fill of this color reads better in black than in white.
    public var prefersDarkLabel: Bool {
        Self.contrast(luminance, Self.darkLabelLuminance) > Self.contrast(luminance, Self.lightLabelLuminance)
    }

    /// The contrast of the better of the two labels on a fill of this color.
    public var labelContrast: Double {
        let fill = luminance
        return max(Self.contrast(fill, Self.darkLabelLuminance), Self.contrast(fill, Self.lightLabelLuminance))
    }

    /// The nearest color, by lightness alone, on which a white or black label reaches `minimum`.
    /// With the WCAG minimum of 4.5 every fill already does; this guards the generator's colors.
    func legible(minimum: Double = 4.5) -> OKLCH {
        guard labelContrast < minimum else { return self }
        for step in 1...160 {
            for direction in [-1.0, 1.0] {
                let candidate = OKLCH(lightness + direction * Double(step) * 0.0025, chroma, hue).inSRGB
                if candidate.labelContrast >= minimum { return candidate }
            }
        }
        return self
    }

    // MARK: - Text

    /// The same color as text: deeper on a light background, lighter on a dark one, until it
    /// reaches `minimum` against `background`, a WCAG luminance. A color that already does is
    /// returned as it is.
    public func readable(onLuminance background: Double, minimum: Double = 4.5) -> OKLCH {
        guard Self.contrast(luminance, background) < minimum else { return self }
        let step = background > 0.18 ? -0.005 : 0.005
        var candidate = self
        for _ in 0..<200 {
            candidate = OKLCH(candidate.lightness + step, chroma, hue).inSRGB
            let reached = Self.contrast(candidate.luminance, background) >= minimum
            if reached || candidate.lightness <= 0 || candidate.lightness >= 1 { break }
        }
        return candidate
    }

    // MARK: - Shades

    public static let white = OKLCH(1, 0, 0)

    /// A lighter, softer companion: where a ring's sweep starts.
    public var highlight: OKLCH {
        OKLCH(min(0.95, lightness + 0.1), chroma * 0.85, hue).inSRGB
    }

    /// The same color, deep enough that white text and symbols on it reach 4.5:1: for icon tiles
    /// and medals, which keep white symbols in light and dark. A color that already holds white
    /// text is returned as it is.
    public var deepened: OKLCH {
        for step in 0...100 {
            let candidate = OKLCH(lightness - Double(step) * 0.01, chroma, hue).inSRGB
            if candidate.contrast(with: .white) >= 4.5 { return candidate }
        }
        return OKLCH(0, 0, hue)
    }

    // MARK: - Helpers

    static func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func cube(_ value: Double) -> Double { value * value * value }

    private static func encode(_ linear: Double) -> Double {
        let value = min(1, max(0, linear))
        return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}

/// Written as `[lightness, chroma, hue]`. A color that isn't three finite numbers fails, so
/// whatever holds it can fall back.
extension OKLCH: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let lightness = try container.decode(Double.self)
        let chroma = try container.decode(Double.self)
        let hue = try container.decode(Double.self)
        guard lightness.isFinite, chroma.isFinite, hue.isFinite else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Not a color"))
        }
        self.init(min(1, max(0, lightness)), max(0, chroma), Hue.normalized(hue))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(lightness)
        try container.encode(chroma)
        try container.encode(hue)
    }
}

/// Angles on the color wheel, in degrees.
enum Hue {
    /// `angle` in 0..<360.
    static func normalized(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        let value = angle.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// The signed shortest turn from `origin` to `angle`, in -180...180.
    static func difference(_ angle: Double, from origin: Double) -> Double {
        let turn = normalized(angle - origin)
        return turn > 180 ? turn - 360 : turn
    }
}
