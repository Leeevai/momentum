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

    var linear: LinearGradient {
        LinearGradient(colors: [color.opacity(0.75), color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The page background: the goal's color fading into black, as watchOS apps do.
    var backdrop: LinearGradient {
        LinearGradient(colors: [color.opacity(0.45), color.opacity(0.08)], startPoint: .top, endPoint: .bottom)
    }
}

/// A goal's ring, Activity style: the goal's color over a dim track, with its symbol inside.
struct WatchRing: View {
    let progress: Double
    let color: GoalColor
    var symbol: String?
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(color.linear, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: lineWidth * 2.2, weight: .semibold))
                    .foregroundStyle(color.color)
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
