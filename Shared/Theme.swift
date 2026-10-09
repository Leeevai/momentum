import MomentumCore
import SwiftUI

extension GoalColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .brown: .brown
        case .gray: .gray
        }
    }

    /// A lighter companion hue for gradients.
    var highlight: Color {
        color.blended(with: .white, by: 0.35)
    }

    /// The ring's sweep: from the light companion into the full color.
    var gradient: AngularGradient {
        AngularGradient(colors: [highlight, color, color], center: .center, startAngle: .degrees(0), endAngle: .degrees(360))
    }

    var linear: LinearGradient {
        LinearGradient(colors: [highlight, color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Goal {
    var tint: Color { color.color }
}

extension Color {
    /// Blends two colors: perceptually on macOS 15 and later, in sRGB before that.
    func blended(with other: Color, by fraction: Double) -> Color {
        if #available(macOS 15.0, *) {
            return self.mix(with: other, by: fraction, in: .perceptual)
        }
        let lhs = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let rhs = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        let mixed = lhs.blended(withFraction: fraction, of: rhs) ?? lhs
        return Color(nsColor: mixed)
    }
}
