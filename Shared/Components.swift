import MomentumCore
import SwiftUI

/// A gradient progress ring. Past 100% it stays closed and gains a soft glow.
struct ProgressRing<Center: View>: View {
    let progress: Double
    let color: GoalColor
    var lineWidth: CGFloat = 8
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(progress, 1)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.color.opacity(progress >= 1 ? 0.45 : 0), radius: lineWidth * 0.6)
                .opacity(progress > 0 ? 1 : 0)
            center
        }
        .padding(lineWidth / 2)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(min(max(progress, 0), 1), format: .percent.precision(.fractionLength(0))))
    }
}

extension ProgressRing where Center == EmptyView {
    init(progress: Double, color: GoalColor, lineWidth: CGFloat = 8) {
        self.init(progress: progress, color: color, lineWidth: lineWidth) { EmptyView() }
    }
}

struct StreakBadge: View {
    let count: Int
    var unit: String = "day"

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .foregroundStyle(count > 0 ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(.tertiary))
            Text("\(count)")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
        }
        .font(.caption.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Goal.streakText(count, unit: unit))
        .help(Goal.streakText(count, unit: unit))
    }
}

/// The goal's symbol on an iOS-style tile: the goal's gradient, a glassy top light, a fine edge
/// and a soft colored shadow.
struct GoalIcon: View {
    let goal: Goal
    var size: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: goal.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(goal.color.linear))
            .overlay(
                shape.fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: max(0.5, size * 0.02)))
            .shadow(color: goal.tint.opacity(0.32), radius: size * 0.14, y: size * 0.07)
            .accessibilityHidden(true)
    }
}

/// The goal's symbol alone, in its color: for ring centers and inline labels.
struct GoalGlyph: View {
    let goal: Goal
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: goal.symbol)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(goal.color.linear)
            .accessibilityHidden(true)
    }
}

/// A GitHub-style grid of days: one column per week, the current week on the right.
/// It fits as many weeks as the space allows.
struct Heatmap: View {
    let engine: ProgressEngine
    let goal: Goal
    let now: Date
    var spacing: CGFloat = 3
    var maxCell: CGFloat = 14
    /// Makes days clickable (to log for that day) and adds a tooltip with the day's amount.
    var onSelect: ((Date) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let cell = max(2, min(maxCell, (geometry.size.height - spacing * 6) / 7))
            let weekCount = max(1, Int((geometry.size.width + spacing) / (cell + spacing)))
            let weeks = Self.weeks(weekCount, endingAt: now, engine: engine)
            HStack(alignment: .top, spacing: spacing) {
                ForEach(weeks.indices, id: \.self) { column in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            cellView(weeks[column][row], size: cell)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity history for \(goal.name)")
    }

    @ViewBuilder
    private func cellView(_ day: Date?, size: CGFloat) -> some View {
        let square = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(fill(for: day))
            .frame(width: size, height: size)
        if let day, let onSelect {
            square
                .help(tooltip(for: day))
                .contentShape(Rectangle())
                .onTapGesture { onSelect(day) }
        } else {
            square
        }
    }

    private func tooltip(for day: Date) -> String {
        let date = day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let amount = engine.amount(for: goal, on: day, now: now)
        switch goal.kind {
        case .milestones:
            return engine.intensity(for: goal, on: day, now: now) > 0 ? "\(date): milestone completed" : date
        case .books:
            return "\(date): \(Formatting.number(amount)) \(Formatting.unit("pages", for: amount))"
        case .time, .count, .amount:
            return "\(date): \(goal.format(amount))"
        }
    }

    private func fill(for day: Date?) -> Color {
        guard let day else { return .clear }
        if day < engine.firstDay(of: goal) { return Color.primary.opacity(0.025) }
        let intensity = engine.intensity(for: goal, on: day, now: now)
        if intensity > 0 { return goal.tint.opacity(0.25 + 0.75 * intensity) }
        return Color.primary.opacity(engine.isRequired(goal, on: day) ? 0.09 : 0.035)
    }

    /// `count` columns of seven days, oldest first, aligned to the calendar's first weekday.
    static func weeks(_ count: Int, endingAt now: Date, engine: ProgressEngine) -> [[Date?]] {
        let today = engine.startOfDay(now)
        let offset = (engine.calendar.component(.weekday, from: today) - engine.calendar.firstWeekday + 7) % 7
        let thisWeek = engine.day(-offset, from: today)
        return (0..<count).map { column in
            let weekStart = engine.day(-7 * (count - 1 - column), from: thisWeek)
            return (0..<7).map { row in
                let day = engine.day(row, from: weekStart)
                return day > today ? nil : day
            }
        }
    }
}

/// A thin capsule progress bar.
struct ProgressBar: View {
    let progress: Double
    let color: GoalColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.color.opacity(0.16))
                Capsule()
                    .fill(color.linear)
                    .frame(width: max(height, geometry.size.width * min(max(progress, 0), 1)))
                    .opacity(progress > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress)
    }
}
