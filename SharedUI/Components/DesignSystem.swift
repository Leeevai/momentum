import MomentumCore
import SwiftUI

// MARK: - Surfaces

/// A pane: a flat fill a step off the ground, under a hairline. No blur, shadow or sheen, so a
/// screen of panes stays calm. A highlighted pane (a running timer) draws its hairline in its
/// tint instead. Named for the frosted glass it replaced.
struct GlassCard: ViewModifier {
    var tint: Color?
    var cornerRadius: CGFloat = GlassTokens.surfaceRadius
    var padding: CGFloat = 16
    var isHighlighted = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let tokens = GlassTokens(colorScheme)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(tokens.fill))
            .overlay {
                shape.strokeBorder(isHighlighted ? (tint ?? palette.colors.accent).opacity(0.55) : tokens.rim,
                                   lineWidth: isHighlighted ? 1 : 0.5)
            }
    }
}

extension View {
    func glassCard(tint: Color? = nil, cornerRadius: CGFloat = GlassTokens.surfaceRadius, padding: CGFloat = 16, highlighted: Bool = false) -> some View {
        modifier(GlassCard(tint: tint, cornerRadius: cornerRadius, padding: padding, isHighlighted: highlighted))
    }

    /// A pane that floats over other content (a toast, a celebration): the system's material, so
    /// it reads over anything, under a hairline, with a soft shadow that lifts it off the screen.
    func floatingPane(padding: CGFloat = 14) -> some View {
        modifier(FloatingPane(padding: padding))
    }
}

private struct FloatingPane: ViewModifier {
    var padding: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: GlassTokens.surfaceRadius, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(.regularMaterial))
            .overlay(shape.strokeBorder(GlassTokens(colorScheme).rim, lineWidth: 0.5))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 16, y: 6)
    }
}

// MARK: - Buttons

/// A round icon button. Prominent ones are a flat disc of the tint; others a neutral well with
/// the symbol in the tint. Presses squash a touch.
struct CircleButtonStyle: ButtonStyle {
    var tint: Color = .accent
    var size: CGFloat = 32
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        CircleButton(configuration: configuration, tint: tint, size: size, prominent: prominent)
    }

    private struct CircleButton: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let size: CGFloat
        let prominent: Bool
        @Environment(\.self) private var environment
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let tokens = GlassTokens(colorScheme)
            configuration.label
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(prominent ? tint.foreground(in: environment) : tint)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(tokens.controlFill))
                        .overlay(Circle().fill(Color.primary.opacity(isHovered ? 0.06 : 0)))
                }
                .scaleEffect(configuration.isPressed ? GlassTokens.pressScale : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
                .contentShape(Circle())
                .onHover { isHovered = $0 }
                .animation(GlassTokens.motion, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
    }
}

// MARK: - Live values

/// Renders `content` with the current time: every second while `isLive`, otherwise once.
/// Keeps the per-second redraw confined to the views that show a running timer.
struct LiveClock<Content: View>: View {
    var isLive: Bool
    var fallback: Date
    @ViewBuilder var content: (Date) -> Content

    var body: some View {
        if isLive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(context.date)
            }
        } else {
            content(fallback)
        }
    }
}

extension View {
    /// Rolls a clock's digits as they change each second. Screenshot runs set `MOMENTUM_SCREENSHOT`
    /// to draw them still, so a capture never lands between two digits.
    func clockTick(_ date: Date) -> some View {
        animation(ClockTick.rolls ? .default : nil, value: Int(date.timeIntervalSince1970))
    }
}

enum ClockTick {
    static let rolls = ProcessInfo.processInfo.environment["MOMENTUM_SCREENSHOT"] == nil
}

/// A running session's elapsed time, or time left for a planned session.
struct SessionClockText: View {
    let session: FocusSession
    var countsDown = true

    var body: some View {
        LiveClock(isLive: session.isRunning, fallback: .now) { now in
            Text(label(at: now))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: countsDown && session.plannedDuration != nil))
                .clockTick(now)
        }
    }

    private func label(at now: Date) -> String {
        if countsDown, let remaining = session.remaining(at: now) {
            return remaining >= 0 ? Formatting.clock(remaining) : "+" + Formatting.clock(-remaining)
        }
        return Formatting.clock(session.elapsed(at: now))
    }
}

// MARK: - Small pieces

extension View {
    /// A section's or a pane's title: small, semibold and secondary, with no icon.
    func paneTitleStyle() -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

/// A section's heading: quiet text, with an optional control on the trailing side.
struct SectionTitle: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .paneTitleStyle()
            Spacer()
            trailing
        }
    }
}

/// A number with its label above and a caption below, for a row of stats in one pane.
struct StatTile: View {
    let title: String
    let value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stats side by side in one pane, wrapping onto more rows at narrow widths.
struct StatGrid<Content: View>: View {
    var minimum: CGFloat = 130
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 16, alignment: .topLeading)], alignment: .leading, spacing: 14) {
            content
        }
        .glassCard()
    }
}

struct CategoryPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            actions
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let previous = rows[rows.count - 1]
                rows.append(Row(y: previous.y + previous.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
