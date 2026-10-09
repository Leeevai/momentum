import MomentumCore
import SwiftUI

// MARK: - Buttons

/// A capsule button, glasscn's Button. Prominent pills are its default variant: a flat fill of the
/// tint with a lit top edge and a glow of the tint, the same on every system. Secondary pills are
/// its tinted variant: tinted Liquid Glass on macOS 26 and iOS 26 (interactive, morphing with
/// other glass in their container), a tinted fill before. Presses squash a touch.
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

        private var wash: Double { colorScheme == .dark ? 0.22 : 0.16 }

        var body: some View {
            let label = configuration.label
                .font((compact ? Font.callout : Font.body).weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, compact ? 14 : 20)
                .padding(.vertical, compact ? 7 : 10)
                .foregroundStyle(prominent ? tint.foreground(in: environment) : tint)
                .contentShape(Capsule())
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, *), !prominent {
                label
                    .glassEffect(.regular.tint(tint.opacity(wash)).interactive(), in: Capsule())
                    .scaleEffect(configuration.isPressed ? GlassTokens.pressScale : 1)
                    .opacity(isEnabled ? 1 : 0.45)
                    .animation(GlassTokens.motion, value: configuration.isPressed)
            } else {
                fallback(label)
            }
            #else
            fallback(label)
            #endif
        }

        private func fallback(_ label: some View) -> some View {
            label
                .background {
                    if prominent {
                        Capsule().fill(tint)
                            // glasscn's inset highlight: a white line along the top edge.
                            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1))
                            .shadow(color: tint.opacity(isHovered ? 0.45 : 0.32), radius: 11, y: 8)
                    } else {
                        Capsule().fill(tint.opacity(isHovered ? wash + 0.08 : wash))
                    }
                }
                .brightness(isHovered && prominent ? 0.05 : 0)
                .scaleEffect(configuration.isPressed ? GlassTokens.pressScale : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
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

    /// A secondary action: a tinted pill, Liquid Glass where the system has it.
    func secondaryActionStyle(_ tint: Color, compact: Bool = false) -> some View {
        buttonStyle(GlassPillStyle(tint: tint, prominent: false, compact: compact))
    }

    /// Joins this view's glass to others with the same id, so they morph into one another as
    /// they appear and disappear (macOS 26). No effect earlier.
    @ViewBuilder
    func glassMorphID(_ id: String, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
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

/// Groups glass shapes so they blend and morph together (macOS 26); a plain stack before.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Rings

/// Concentric rings, one per goal, like Activity rings: today's progress at a glance.
struct RingStack: View {
    let rings: [(goal: Goal, progress: Double)]
    var lineWidth: CGFloat = 14
    var spacing: CGFloat = 4

    var body: some View {
        ZStack {
            ForEach(Array(rings.prefix(4).enumerated()), id: \.element.goal.id) { index, ring in
                let inset = CGFloat(index) * (lineWidth + spacing)
                ZStack {
                    Circle()
                        .stroke(ring.goal.tint.opacity(0.16), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: max(0.0001, min(ring.progress, 1)))
                        .stroke(ring.goal.color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: ring.goal.tint.opacity(ring.progress >= 1 ? 0.5 : 0.25), radius: lineWidth * 0.35)
                        .opacity(ring.progress > 0 ? 1 : 0)
                }
                .padding(inset + lineWidth / 2)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: rings.map(\.progress))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rings.map { "\($0.goal.name) \(Int(($0.progress * 100).rounded())) percent" }.joined(separator: ", "))
    }
}
