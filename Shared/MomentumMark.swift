import SwiftUI

/// The app's mark, as on its icon: a spiral ribbon that opens out from a fine indigo thread at its
/// heart, through violet and coral, to a bold orange head (small steps, compounding into momentum). It draws itself in when it
/// appears, growing outward from the heart.
struct MomentumMark: View {
    var size: CGFloat
    var animated: Bool

    @State private var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A still mark starts drawn, so it shows in an image rendered off screen too.
    init(size: CGFloat = 120, animated: Bool = true) {
        self.size = size
        self.animated = animated
        _progress = State(initialValue: animated ? 0 : 1)
    }

    static let coral = Color(red: 1.00, green: 0.35, blue: 0.37)

    var body: some View {
        ZStack {
            MomentumSpiral(progress: progress)
                .fill(MomentumSpiral.gradient(side: size))
                .shadow(color: Self.coral.opacity(0.3), radius: size * 0.04)
            // The bright head, where the motion is, once the spiral reaches it.
            let head = MomentumSpiral.point(1)
            Circle()
                .fill(.white)
                .frame(width: MomentumSpiral.halfWidth(1) * size, height: MomentumSpiral.halfWidth(1) * size)
                .shadow(color: Color(red: 1.0, green: 0.70, blue: 0.48), radius: MomentumSpiral.halfWidth(1) * size * 0.6)
                .position(x: head.x * size, y: head.y * size)
                .opacity(progress >= 1 ? 1 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear(perform: drawIn)
    }

    private func drawIn() {
        guard animated, !reduceMotion else {
            progress = 1
            return
        }
        withAnimation(.easeOut(duration: 1.1)) { progress = 1 }
    }
}

/// The icon's spiral as a shape: a logarithmic spiral of 2.2 turns whose ribbon thickens as it
/// opens, fitted to its frame. `progress` draws it from the heart (0) out to the head (1).
/// scripts/make_icon.swift draws the same spiral for the app icon: keep the two in step.
struct MomentumSpiral: Shape {
    var progress: Double = 1

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let turns = 2.2
    private static let innerRadius = 0.03
    private static let outerRadius = 0.34
    private static let total = turns * 2 * .pi
    private static let growth = log(outerRadius / innerRadius) / total

    private static func rawHalfWidth(_ t: Double) -> Double { 0.004 + 0.058 * pow(t, 1.4) }

    /// The centre line at `t`, around the origin, y up.
    private static func raw(_ t: Double) -> CGPoint {
        let theta = total * t
        let r = innerRadius * exp(growth * theta)
        let angle = theta - total + .pi * 0.3
        return CGPoint(x: r * cos(angle), y: r * sin(angle))
    }

    /// The ribbon's bounds, y up: their middle and their longer side.
    private static let bounds: (mid: CGPoint, span: Double) = {
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for i in 0...600 {
            let t = Double(i) / 600, p = raw(t), w = rawHalfWidth(t)
            minX = min(minX, p.x - w); maxX = max(maxX, p.x + w)
            minY = min(minY, p.y - w); maxY = max(maxY, p.y + w)
        }
        return (CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2), max(maxX - minX, maxY - minY))
    }()

    /// A point in a unit square the ribbon fills, y down.
    private static func fitted(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - bounds.mid.x) / bounds.span + 0.5, y: 0.5 - (p.y - bounds.mid.y) / bounds.span)
    }

    /// The centre line at `t`, in the unit square.
    static func point(_ t: Double) -> CGPoint { fitted(raw(t)) }

    /// The ribbon's half-width at `t`, as a fraction of the square's side.
    static func halfWidth(_ t: Double) -> Double { rawHalfWidth(t) / bounds.span }

    /// Indigo at the heart through violet and coral to orange at the head. The spiral's radius
    /// grows with `t`, so a radial gradient from its centre colours it along its length.
    static func gradient(side: CGFloat) -> RadialGradient {
        let colors: [(Double, Color)] = [
            (0, Color(red: 0.23, green: 0.23, blue: 0.84)), (0.45, Color(red: 0.48, green: 0.25, blue: 0.88)),
            (0.75, MomentumMark.coral), (1, Color(red: 1.00, green: 0.54, blue: 0.24)),
        ]
        let stops = colors.map { t, color in
            Gradient.Stop(color: color, location: pow(innerRadius / outerRadius, 1 - t))
        }
        let centre = fitted(.zero)
        return RadialGradient(stops: stops, center: UnitPoint(x: centre.x, y: centre.y),
                              startRadius: 0, endRadius: outerRadius / bounds.span * side)
    }

    func path(in rect: CGRect) -> Path {
        let end = min(1, max(0, progress))
        guard end > 0 else { return Path() }
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func scaled(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * side, y: origin.y + p.y * side) }

        // Both edges of the ribbon, offset from the centre line along its normal.
        let count = 320
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        var tangent = CGPoint(x: 1, y: 0)
        for i in 0...count {
            let t = end * Double(i) / Double(count)
            let p = Self.point(t)
            let ahead = Self.point(min(1, t + 0.001)), behind = Self.point(max(0, t - 0.001))
            let length = max(1e-9, hypot(ahead.x - behind.x, ahead.y - behind.y))
            tangent = CGPoint(x: (ahead.x - behind.x) / length, y: (ahead.y - behind.y) / length)
            let w = Self.halfWidth(t)
            outer.append(scaled(CGPoint(x: p.x - tangent.y * w, y: p.y + tangent.x * w)))
            inner.append(scaled(CGPoint(x: p.x + tangent.y * w, y: p.y - tangent.x * w)))
        }
        var path = Path()
        path.move(to: outer[0])
        for p in outer.dropFirst() { path.addLine(to: p) }
        // A round cap at the head: half a circle from the outer edge, through the tip, to the inner.
        let head = scaled(Self.point(end)), radius = Self.halfWidth(end) * side
        let start = atan2(tangent.x, -tangent.y) // the outer normal's angle; turning back from it reaches the tip
        for k in 1..<24 {
            let angle = start - .pi * Double(k) / 24
            path.addLine(to: CGPoint(x: head.x + radius * cos(angle), y: head.y + radius * sin(angle)))
        }
        for p in inner.reversed() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}
