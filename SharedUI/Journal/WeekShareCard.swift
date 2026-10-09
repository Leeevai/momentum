import MomentumCore
import SwiftUI

/// The week in review as an image to share: focus, perfect days, each goal's record and the
/// wins. Pure shapes and text, so `ImageRenderer` draws it faithfully.
struct WeekShareCard: View {
    let review: WeekReview
    let goals: [Goal]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("My week")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(rangeText)
                        .font(.system(size: 15, weight: .medium))
                        .opacity(0.8)
                }
                Spacer()
                MomentumMark(size: 54, animated: false)
            }
            HStack(spacing: 14) {
                figure(Formatting.duration(review.focusSeconds), "focused", symbol: "timer")
                figure("\(review.perfectDays)/7", "perfect days", symbol: "star.fill")
                figure("\(review.activeDays)/7", "active days", symbol: "flame.fill")
            }
            if !goals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(rows, id: \.goal.id) { row in
                        HStack(spacing: 12) {
                            Image(systemName: row.goal.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(row.goal.tint))
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(row.goal.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(row.text)
                                        .font(.system(size: 13, weight: .medium))
                                        .opacity(0.8)
                                }
                                if let fraction = row.fraction {
                                    GeometryReader { proxy in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(.white.opacity(0.2))
                                            if fraction > 0 {
                                                Capsule().fill(.white).frame(width: max(6, proxy.size.width * fraction))
                                            }
                                        }
                                    }
                                    .frame(height: 6)
                                }
                            }
                        }
                    }
                }
            }
            if !review.wins.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(review.wins.suffix(3)) { win in
                        Label(win.text, systemImage: "trophy.fill")
                            .font(.system(size: 15, weight: .medium))
                            .lineLimit(1)
                    }
                }
            }
            HStack {
                Text("Tracked with Momentum")
                Spacer()
                if let best = review.bestDay {
                    Text("Best day: \(best.formatted(.dateTime.weekday(.wide)))")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .opacity(0.75)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(width: 560)
        .background(
            LinearGradient(colors: [Color(red: 0.13, green: 0.55, blue: 0.62), Color(red: 0.24, green: 0.2, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private struct Row {
        let goal: Goal
        /// Days kept of days due, for daily goals; others show what was logged instead.
        let fraction: Double?
        let text: String
    }

    /// The goals with something to show, best record first, at most five.
    private var rows: [Row] {
        let byID = Dictionary(goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return review.goals.compactMap { week -> Row? in
            guard let goal = byID[week.goalID] else { return nil }
            let daily = goal.effectivePeriod == .daily && goal.kind != .milestones && goal.kind != .books
            guard daily else {
                return Row(goal: goal, fraction: nil, text: week.amount > 0 ? goal.formatLogged(week.amount) : "In progress")
            }
            let fraction = week.due > 0 ? Double(week.met) / Double(week.due) : 0
            return Row(goal: goal, fraction: min(1, fraction), text: "\(week.met) of \(week.due) days")
        }
        .sorted { ($0.fraction ?? -1) > ($1.fraction ?? -1) }
        .prefix(5)
        .map { $0 }
    }

    private var rangeText: String {
        review.range.start.formatted(.dateTime.month(.abbreviated).day()) + " to "
            + review.range.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day())
    }

    private func figure(_ value: String, _ label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .opacity(0.85)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.14)))
    }

    /// Renders the card at 2x for crisp sharing.
    @MainActor
    static func image(review: WeekReview, goals: [Goal]) -> PlatformImage? {
        let renderer = ImageRenderer(content: WeekShareCard(review: review, goals: goals).environment(\.colorScheme, .dark))
        renderer.scale = 2
        #if os(macOS)
        return renderer.nsImage
        #else
        return renderer.uiImage
        #endif
    }
}
