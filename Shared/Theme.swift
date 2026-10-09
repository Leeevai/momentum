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
    /// Blends two colors: perceptually on macOS 15 and iOS 18 and later, in sRGB before that.
    func blended(with other: Color, by fraction: Double) -> Color {
        if #available(macOS 15.0, iOS 18.0, *) {
            return self.mix(with: other, by: fraction, in: .perceptual)
        }
        #if canImport(AppKit)
        let lhs = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let rhs = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        let mixed = lhs.blended(withFraction: fraction, of: rhs) ?? lhs
        return Color(nsColor: mixed)
        #else
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(fraction)
        return Color(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, opacity: a1 + (a2 - a1) * t)
        #endif
    }
}

extension Color {
    /// The window's background: behind content, and the base glass is laid over.
    static var windowBackground: Color {
        #if canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
}

extension View {
    /// Runs `action` on Escape (macOS); a no-op where there is no Escape key to speak of.
    @ViewBuilder
    func onEscape(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}
