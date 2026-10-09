import MomentumCore
import SwiftUI

// MARK: - Backdrop

/// A soft field of color behind a screen, so Liquid Glass has something to refract. A mesh
/// gradient on macOS 15 and later; layered radial gradients before that. Static on purpose:
/// an animated backdrop costs GPU on every frame for very little.
struct LivingBackdrop: View {
    var primary: Color
    var secondary: Color = .purple
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let base = Color(nsColor: .windowBackgroundColor)
        let a = primary.opacity(dark ? 0.42 : 0.28)
        let b = secondary.opacity(dark ? 0.32 : 0.22)
        let c = primary.blended(with: secondary, by: 0.5).opacity(dark ? 0.24 : 0.16)
        ZStack {
            base
            if #available(macOS 15.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [[0, 0], [0.55, 0], [1, 0], [0, 0.5], [0.45, 0.55], [1, 0.45], [0, 1], [0.6, 1], [1, 1]],
                    colors: [a, c, b, c.opacity(0.6), base.opacity(0), b.opacity(0.7), base.opacity(0), a.opacity(0.5), base.opacity(0)]
                )
            } else {
                RadialGradient(colors: [a, .clear], center: .topLeading, startRadius: 0, endRadius: 650)
                RadialGradient(colors: [b, .clear], center: .topTrailing, startRadius: 0, endRadius: 520)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: primary)
    }
}

// MARK: - Buttons

/// A capsule button. Prominent pills are a vivid gradient with a glassy sheen, identical on every
/// macOS and active or not. Secondary pills are tinted Liquid Glass on macOS 26 (interactive,
/// morphing with other glass in their container) and a tinted fill before.
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
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let label = configuration.label
                .font((compact ? Font.callout : Font.body).weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, compact ? 13 : 18)
                .padding(.vertical, compact ? 7 : 10)
                .foregroundStyle(prominent ? Color.white : tint)
                .contentShape(Capsule())
            #if compiler(>=6.2)
            if #available(macOS 26.0, *), !prominent {
                label
                    .glassEffect(.regular.tint(tint.opacity(0.14)).interactive(), in: Capsule())
                    .scaleEffect(configuration.isPressed ? 0.96 : 1)
                    .opacity(isEnabled ? 1 : 0.45)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
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
                    Capsule().fill(prominent
                        ? AnyShapeStyle(LinearGradient(colors: [tint.blended(with: .white, by: 0.18), tint], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(tint.opacity(isHovered ? 0.2 : 0.13)))
                }
                .overlay {
                    if prominent {
                        // A glassy sheen across the top, as on iOS buttons.
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)], startPoint: .top, endPoint: .center))
                            .blendMode(.plusLighter)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0.22 : 0), lineWidth: 1))
                .shadow(color: prominent ? tint.opacity(isHovered ? 0.45 : 0.28) : .clear, radius: isHovered ? 10 : 6, y: 3)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
    }
}

extension View {
    /// The main action: a tinted Liquid Glass pill.
    func primaryActionStyle(_ tint: Color, compact: Bool = false) -> some View {
        buttonStyle(GlassPillStyle(tint: tint, prominent: true, compact: compact))
    }

    /// A secondary action: a clear Liquid Glass pill in the tint.
    func secondaryActionStyle(_ tint: Color, compact: Bool = false) -> some View {
        buttonStyle(GlassPillStyle(tint: tint, prominent: false, compact: compact))
    }

    /// Joins this view's glass to others with the same id, so they morph into one another as
    /// they appear and disappear (macOS 26). No effect earlier.
    @ViewBuilder
    func glassMorphID(_ id: String, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
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
        if #available(macOS 26.0, *) {
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
