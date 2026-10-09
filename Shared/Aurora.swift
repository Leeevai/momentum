import MomentumCore
import SwiftUI

/// glasscn's aurora, the ground glass sits on: three soft palette blobs drifting over the
/// palette's base color. Each blob is a radial gradient moved and scaled by a transform, so the
/// drift is cheap to draw; it stands still with Reduce Motion, in Low Power Mode, and in widgets.
struct Aurora: View {
    /// A color for the first blob in place of the palette's, to re-theme one screen (a goal's).
    var accent: Color?
    var animates = true
    /// Scales the blobs' minimum sizes, glasscn's aurora scale: small for a swatch.
    var scale: CGFloat = 1

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifted = false

    var body: some View {
        let dark = colorScheme == .dark
        let tokens = palette.tokens(dark: dark)
        let first = accent.map { $0.opacity(dark ? 0.62 : 0.5) } ?? Color(tokens.aurora[0])
        let moving = animates && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(tokens.auroraBase)
                // Positions, sizes, drift and periods are glasscn's.
                blob(first, in: proxy.size, origin: CGPoint(x: -0.25, y: -0.15), width: 1.25, minimum: 560,
                     drift: CGSize(width: 0.06, height: 0.04), zoom: (1, 1.08), period: 34, moving: moving)
                blob(Color(tokens.aurora[1]), in: proxy.size, origin: CGPoint(x: 0.4, y: 0.1), width: 1.05, minimum: 480,
                     drift: CGSize(width: -0.05, height: 0.06), zoom: (1, 1.06), period: 42, moving: moving)
                blob(Color(tokens.aurora[2]), in: proxy.size, origin: CGPoint(x: -0.1, y: 0.55), width: 1.2, minimum: 540,
                     drift: CGSize(width: 0.04, height: -0.06), zoom: (1.04, 1), period: 38, moving: moving)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.6), value: palette)
        .onAppear { if moving { drifted = true } }
    }

    /// One blob: `origin` and `width` are fractions of the container's width and height, as CSS
    /// percentages are; the drift is a fraction of the blob's own size, swinging out and back
    /// over `period` seconds.
    private func blob(_ color: Color, in size: CGSize, origin: CGPoint, width: CGFloat, minimum: CGFloat,
                      drift: CGSize, zoom: (CGFloat, CGFloat), period: Double, moving: Bool) -> some View {
        let diameter = max(size.width * width, minimum * self.scale)
        return Circle()
            .fill(RadialGradient(stops: [
                .init(color: color, location: 0),
                .init(color: color.opacity(0.55), location: 0.45),
                .init(color: color.opacity(0), location: 1),
            ], center: .center, startRadius: 0, endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
            .scaleEffect(drifted ? zoom.1 : zoom.0)
            .offset(x: size.width * origin.x + (drifted ? diameter * drift.width : 0),
                    y: size.height * origin.y + (drifted ? diameter * drift.height : 0))
            .animation(moving ? .easeInOut(duration: period / 2).repeatForever(autoreverses: true) : nil, value: drifted)
    }
}
