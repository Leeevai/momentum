import Foundation

extension OKLCH {
    /// A plain name for the color as it looks, for VoiceOver: "Blue", "Deep teal", "Gray". A
    /// goal's color is named by its swatch rather than its stored name, which in a palette of
    /// one hue can be a shade of something else entirely.
    public var name: String {
        let base: String
        let angle = Hue.normalized(hue)
        if chroma < 0.03 {
            base = "gray"
        } else if angle >= 40 && angle < 105 && chroma < 0.06 {
            base = "brown"
        } else {
            base = Self.hueNames.first { angle < $0.below }?.name ?? "pink"
        }
        let shade = lightness < 0.47 ? "Deep " : lightness > 0.62 ? "Light " : ""
        return shade.isEmpty ? base.capitalized : shade + base
    }

    /// Hue names by where each ends on the wheel, in OKLCH degrees.
    private static let hueNames: [(below: Double, name: String)] = [
        (15, "pink"), (40, "red"), (75, "orange"), (115, "yellow"), (160, "green"), (185, "mint"),
        (210, "teal"), (235, "cyan"), (268, "blue"), (295, "indigo"), (330, "purple"), (360, "pink"),
    ]
}
