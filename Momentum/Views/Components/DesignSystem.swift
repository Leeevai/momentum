import MomentumCore
import SwiftUI

// MARK: - Surfaces

/// A rounded content card: Liquid Glass on macOS 26 and later, a material on earlier systems.
struct GlassCard: ViewModifier {
    var tint: Color?
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 18
    var isHighlighted = false

    @ViewBuilder
    func body(content: Content) -> some View {
        // Liquid Glass needs the macOS 26 SDK (Swift 6.2) to compile, and macOS 26 to run.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            glass(content)
        } else {
            material(content)
        }
        #else
        material(content)
        #endif
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func glass(_ content: Content) -> some View {
        content
            .padding(padding)
            .glassEffect(.regular.tint(tint?.opacity(isHighlighted ? 0.22 : 0.08)), in: shape)
            .overlay(shape.strokeBorder(tint?.opacity(isHighlighted ? 0.7 : 0) ?? .clear, lineWidth: 1.5))
    }
    #endif

    private func material(_ content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: shape)
            .background(shape.fill((tint ?? .clear).opacity(isHighlighted ? 0.12 : 0.04)))
            .overlay(shape.strokeBorder(isHighlighted ? (tint ?? .accentColor).opacity(0.7) : Color.primary.opacity(0.07), lineWidth: isHighlighted ? 1.5 : 1))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    func glassCard(tint: Color? = nil, cornerRadius: CGFloat = 18, padding: CGFloat = 18, highlighted: Bool = false) -> some View {
        modifier(GlassCard(tint: tint, cornerRadius: cornerRadius, padding: padding, isHighlighted: highlighted))
    }
}

// MARK: - Buttons

/// A capsule button. Prominent buttons fill with the tint's gradient; others are tinted glass.
struct PillButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var prominent = true
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, tint: tint, prominent: prominent, compact: compact)
    }

    private struct PillButton: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font((compact ? Font.callout : Font.body).weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, compact ? 12 : 16)
                .padding(.vertical, compact ? 6 : 9)
                .foregroundStyle(prominent ? Color.white : tint)
                .background {
                    Capsule().fill(prominent
                        ? AnyShapeStyle(LinearGradient(colors: [tint.blended(with: .white, by: 0.18), tint], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(tint.opacity(isHovered ? 0.2 : 0.13)))
                }
                .overlay(Capsule().strokeBorder(.white.opacity(prominent ? 0.18 : 0), lineWidth: 1))
                .shadow(color: prominent ? tint.opacity(isHovered ? 0.45 : 0.28) : .clear, radius: isHovered ? 10 : 6, y: 3)
                .brightness(isHovered && prominent ? 0.04 : 0)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Capsule())
                .onHover { isHovered = $0 }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
    }
}

/// A round icon button.
struct CircleButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var size: CGFloat = 32
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(prominent ? Color.white : tint)
            .frame(width: size, height: size)
            .background(Circle().fill(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14))))
            .shadow(color: prominent ? tint.opacity(0.3) : .clear, radius: 5, y: 2)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .contentShape(Circle())
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
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

/// A running session's elapsed time, or time left for a planned session.
struct SessionClockText: View {
    let session: FocusSession
    var countsDown = true

    var body: some View {
        LiveClock(isLive: session.isRunning, fallback: .now) { now in
            Text(label(at: now))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: countsDown && session.plannedDuration != nil))
                .animation(.default, value: Int(now.timeIntervalSince1970))
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

struct SectionTitle: View {
    let title: String
    var systemImage: String?
    var trailing: AnyView?

    init(_ title: String, systemImage: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
            Spacer()
            trailing
        }
        .font(.headline)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
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
        .glassCard(tint: tint, padding: 14)
    }
}

struct CategoryPill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(tint)
            .background(Capsule().fill(tint.opacity(0.13)))
    }
}

struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, options: .repeating.speed(0.4))
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            actions
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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
