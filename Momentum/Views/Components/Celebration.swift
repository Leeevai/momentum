import MomentumCore
import SwiftUI

/// Confetti and a toast when a goal hits its target. Dismisses itself.
struct CelebrationOverlay: View {
    let celebration: Celebration
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var toastVisible = false

    var body: some View {
        ZStack(alignment: .top) {
            if !reduceMotion {
                TimelineView(.animation) { context in
                    Canvas { canvas, size in
                        let elapsed = context.date.timeIntervalSince(start)
                        for particle in Self.particles {
                            draw(particle, at: elapsed, in: &canvas, size: size)
                        }
                    }
                }
                .allowsHitTesting(false)
            }

            if toastVisible {
                HStack(spacing: 12) {
                    GoalIcon(goal: celebration.goal, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(celebration.goal.name) complete")
                            .font(.headline)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .glassCard(tint: celebration.goal.tint, cornerRadius: 22, padding: 0, highlighted: true)
                .padding(.top, 24)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { toastVisible = true }
            try? await Task.sleep(for: .seconds(2.6))
            withAnimation(.easeIn(duration: 0.3)) { toastVisible = false }
            try? await Task.sleep(for: .seconds(0.4))
            onFinish()
        }
    }

    private var subtitle: String {
        let period = celebration.goal.effectivePeriod
        return period == .total ? "Target reached. Brilliant." : "\(period.currentLabel)'s target reached. Keep it rolling."
    }

    private struct Particle {
        var x: Double
        var delay: Double
        var speed: Double
        var drift: Double
        var spin: Double
        var size: Double
        var hue: Double
    }

    private static let particles: [Particle] = (0..<140).map { index in
        var generator = SystemRandomNumberGenerator()
        func random(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &generator) }
        return Particle(x: random(0...1), delay: random(0...0.5), speed: random(260...520), drift: random(-90...90),
                        spin: random(-8...8), size: random(5...10), hue: Double(index % 7) / 7)
    }

    private func draw(_ particle: Particle, at elapsed: Double, in canvas: inout GraphicsContext, size: CGSize) {
        let t = elapsed - particle.delay
        guard t > 0 else { return }
        let y = -20 + particle.speed * t + 120 * t * t
        guard y < size.height + 20 else { return }
        let x = particle.x * size.width + particle.drift * sin(t * 2.4)
        let opacity = max(0, 1 - max(0, t - 2.2) / 0.6)
        var context = canvas
        context.opacity = opacity
        context.translateBy(x: x, y: y)
        context.rotate(by: .radians(particle.spin * t))
        let rect = CGRect(x: -particle.size / 2, y: -particle.size / 4, width: particle.size, height: particle.size / 2)
        context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Color(hue: particle.hue, saturation: 0.75, brightness: 0.98)))
    }
}
