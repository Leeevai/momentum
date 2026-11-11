import MomentumCore
import SwiftUI

// MARK: - Buttons

/// A capsule button. Prominent pills are a flat fill of the tint, for the one main action in a
/// place; secondary pills a neutral fill with the label in the tint. No glow, sheen or glass.
/// Presses squash a touch.
struct GlassPillStyle: ButtonStyle {
    var tint: Color
    var prominent = true
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        GlassPill(configuration: configuration, tint: tint, prominent: prominent, compact: compact)
    }

    private struct GlassPill: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let prominent: Bool
        let compact: Bool
        @Environment(\.self) private var environment
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let tokens = GlassTokens(colorScheme)
            configuration.label
                .font((compact ? Font.callout : Font.body).weight(.medium))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, compact ? 12 : 18)
                .padding(.vertical, compact ? 6 : 9)
                .foregroundStyle(prominent ? tint.foreground(in: environment) : tint)
                .background {
                    Capsule().fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(tokens.controlFill))
                        .overlay(Capsule().fill(Color.primary.opacity(isHovered ? 0.06 : 0)))
                }
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? GlassTokens.pressScale : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
                .onHover { isHovered = $0 }
                .animation(GlassTokens.motion, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
    }
}

extension View {
    /// The main action: a filled pill in the tint.
    func primaryActionStyle(_ tint: Color, compact: Bool = false) -> some View {
        buttonStyle(GlassPillStyle(tint: tint, prominent: true, compact: compact))
    }

    /// A secondary action: a neutral pill with its label in the tint.
    func secondaryActionStyle(_ tint: Color, compact: Bool = false) -> some View {
        buttonStyle(GlassPillStyle(tint: tint, prominent: false, compact: compact))
    }
}

extension View {
    /// Matches this view's geometry to a hero counterpart when a namespace is given, so it morphs
    /// between places (a Today card and its expanded page).
    @ViewBuilder
    func heroMatch(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Rings

/// Concentric rings, one per goal, like Activity rings: today's progress at a glance, lapping
/// past 100%.
struct RingStack: View {
    let rings: [(goal: Goal, progress: Double)]
    var lineWidth: CGFloat = 14
    var spacing: CGFloat = 4
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            ForEach(Array(rings.prefix(4).enumerated()), id: \.element.goal.id) { index, ring in
                let inset = CGFloat(index) * (lineWidth + spacing)
                let tint = palette.color(ring.goal.color)
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.14), lineWidth: lineWidth)
                    RingSweep(progress: ring.progress, color: ring.goal.color, lineWidth: lineWidth)
                }
                .padding(inset + lineWidth / 2)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: rings.map(\.progress))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rings.map { "\($0.goal.name) \(Int(($0.progress * 100).rounded())) percent" }.joined(separator: ", "))
    }
}
