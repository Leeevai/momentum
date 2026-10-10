import MomentumCore
import SwiftUI

extension Color {
    /// A palette color, defined in OKLCH.
    init(_ oklch: OKLCH) {
        let rgb = oklch.sRGB
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension EnvironmentValues {
    /// The palette the iPhone sent, or the default one until it has.
    @Entry var watchPalette: WatchPalette = .standard
}

extension WatchPalette {
    /// A goal color's swatch.
    func color(_ goalColor: GoalColor) -> Color { Color(swatch(goalColor)) }

    /// The palette's accent.
    var accentColor: Color { Color(accent) }

    /// Streaks and their flames.
    var streak: Color { color(.orange) }
    /// Done.
    var success: Color { color(.green) }
    /// Breaks between focus blocks.
    var rest: Color { color(.mint) }

    func linear(_ goalColor: GoalColor) -> LinearGradient {
        let tint = color(goalColor)
        return LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A page's background: the goal's color fading into black, as watchOS apps do.
    func backdrop(_ goalColor: GoalColor) -> LinearGradient {
        let tint = color(goalColor)
        return LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.08)], startPoint: .top, endPoint: .bottom)
    }
}

/// A goal's ring, Activity style: the goal's color over a dim track, with its symbol inside.
struct WatchRing: View {
    let progress: Double
    let color: GoalColor
    var symbol: String?
    var lineWidth: CGFloat = 5
    @Environment(\.watchPalette) private var palette

    var body: some View {
        let tint = palette.color(color)
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(palette.linear(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: lineWidth * 2.2, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .padding(lineWidth / 2)
        .animation(.spring(duration: 0.5), value: progress)
    }
}

extension FocusSession {
    /// When the clock reads zero: now minus the time already focused, for a counting-up timer.
    func clockStart(at now: Date = .now) -> Date {
        now.addingTimeInterval(-elapsed(at: now))
    }
}
