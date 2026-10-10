import MomentumCore
import SwiftUI

/// The app's mark, as on its icon: a sweeping ring around a dark glass disc with an arrow, drawn in
/// the palette's accent so it sits with the rest of the screen. It draws itself in when it appears.
struct MomentumMark: View {
    var size: CGFloat
    var animated: Bool

    @State private var sweep: Double
    @State private var showsArrow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    /// A still mark starts drawn, so it shows in an image rendered off screen too.
    init(size: CGFloat = 120, animated: Bool = true) {
        self.size = size
        self.animated = animated
        _sweep = State(initialValue: animated ? 0 : 1)
        _showsArrow = State(initialValue: !animated)
    }

    /// How much of the circle the ring covers, leaving the icon's gap at the top left.
    private static let arc = 0.81

    var body: some View {
        let line = size * 0.13
        let colors = palette.colors
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: line)
            ring(line: line, colors: colors)
            Circle()
                .fill(LinearGradient(colors: [colors.accentDeep, colors.accentDeep.blended(with: .black, by: 0.4)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: max(1, size * 0.012)))
                .frame(width: size * 0.5, height: size * 0.5)
                .shadow(color: colors.accent.opacity(0.35), radius: size * 0.08, y: size * 0.03)
            Image(systemName: "arrow.up.right")
                .font(.system(size: size * 0.2, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .scaleEffect(showsArrow ? 1 : 0.3)
                .opacity(showsArrow ? 1 : 0)
        }
        .frame(width: size, height: size)
        .padding(line / 2)
        .accessibilityHidden(true)
        .onAppear(perform: drawIn)
    }

    /// Drawn clockwise from the top in a mirrored frame, so on screen it runs counterclockwise
    /// from ten o'clock, the way the icon reads: light at the start, deep at the end.
    private func ring(line: CGFloat, colors: PaletteColors) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Self.arc * sweep)
                .stroke(AngularGradient(colors: [colors.accentHighlight, colors.accentHighlight, colors.accent, colors.accentDeep],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * Self.arc)),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .shadow(color: colors.accent.opacity(0.45), radius: line * 0.7)
            // The bright starting point.
            Circle()
                .fill(colors.accentHighlight)
                .frame(width: line * 0.8, height: line * 0.8)
                .blur(radius: line * 0.08)
                .offset(x: size / 2)
                .opacity(sweep > 0 ? 1 : 0)
        }
        .rotationEffect(.degrees(-30))
        .scaleEffect(x: -1)
    }

    private func drawIn() {
        guard animated, !reduceMotion else {
            sweep = 1
            showsArrow = true
            return
        }
        withAnimation(.spring(duration: 1.3, bounce: 0.12)) { sweep = 1 }
        withAnimation(.spring(duration: 0.6, bounce: 0.5).delay(0.55)) { showsArrow = true }
    }
}
