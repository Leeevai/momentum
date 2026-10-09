import MomentumCore
import SwiftUI

// MARK: - Surfaces

/// A pane of glass, glasscn's surface. Liquid Glass on macOS 26 and iOS 26, tinted so it reads on
/// the aurora; a frosted material before, under glasscn's fill, sheen, rim, highlight and shadow.
/// Highlighted panes (a running timer) take a wash and a rim of their tint.
struct GlassCard: ViewModifier {
    var tint: Color?
    var cornerRadius: CGFloat = GlassTokens.surfaceRadius
    var padding: CGFloat = 18
    var isHighlighted = false
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        // Liquid Glass needs the macOS 26 SDK (Swift 6.2) to compile, and macOS 26 to run.
        #if compiler(>=6.2)
        if #available(macOS 26.0, iOS 26.0, *) {
            glass(content)
        } else {
            frosted(content)
        }
        #else
        frosted(content)
        #endif
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var highlightRim: some View {
        shape.strokeBorder((tint ?? .accent).opacity(isHighlighted ? 0.7 : 0), lineWidth: 1.5)
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, iOS 26.0, *)
    private func glass(_ content: Content) -> some View {
        let tokens = GlassTokens(colorScheme)
        return content
            .padding(padding)
            .glassEffect(.regular.tint(isHighlighted ? (tint ?? .accent).opacity(0.22) : tokens.liquidTint), in: shape)
            .overlay(highlightRim)
    }
    #endif

    private func frosted(_ content: Content) -> some View {
        let tokens = GlassTokens(colorScheme)
        return content
            .padding(padding)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(isHighlighted ? (tint ?? .accent).opacity(0.16) : tokens.fill)
                    // glasscn's sheen: a 160-degree wash of white, gone halfway down.
                    shape.fill(LinearGradient(stops: [.init(color: .white.opacity(tokens.sheen), location: 0),
                                                      .init(color: .white.opacity(0), location: 0.55)],
                                              startPoint: UnitPoint(x: 0.33, y: 0.03), endPoint: UnitPoint(x: 0.67, y: 0.97)))
                }
                .compositingGroup()
                .shadow(color: tokens.shadow, radius: GlassTokens.shadowRadius, y: GlassTokens.shadowY)
            }
            .overlay {
                // The rim, brightest along the top edge where the light catches it.
                shape.strokeBorder(LinearGradient(colors: [tokens.highlight, tokens.rim], startPoint: .top,
                                                  endPoint: UnitPoint(x: 0.5, y: 0.15)), lineWidth: 1)
            }
            .overlay(highlightRim)
    }
}

extension View {
    func glassCard(tint: Color? = nil, cornerRadius: CGFloat = GlassTokens.surfaceRadius, padding: CGFloat = 18, highlighted: Bool = false) -> some View {
        modifier(GlassCard(tint: tint, cornerRadius: cornerRadius, padding: padding, isHighlighted: highlighted))
    }
}

// MARK: - Buttons

/// A round icon button: glasscn's icon button. Prominent ones fill with the tint, under a lit top
/// edge and a glow of the tint; others are a soft tinted well. Presses squash a touch.
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
            configuration.label
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(prominent ? tint.foreground(in: environment) : tint)
                .frame(width: size, height: size)
                .background {
                    if prominent {
                        Circle().fill(tint)
                            .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1))
                            .shadow(color: tint.opacity(isHovered ? 0.45 : 0.32), radius: size * 0.22, y: size * 0.12)
                    } else {
                        Circle().fill(tint.opacity(colorScheme == .dark ? 0.22 : 0.16))
                            .overlay(Circle().fill(tint.opacity(isHovered ? 0.08 : 0)))
                    }
                }
                .brightness(isHovered && prominent ? 0.04 : 0)
                .scaleEffect(configuration.isPressed ? GlassTokens.pressScale : 1)
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
                .contentShape(Circle())
                .onHover { isHovered = $0 }
                .animation(GlassTokens.motion, value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
    }
}

extension Color {
    /// Text and icons on a fill of this color: white, or near-black on the lightest fills (the
    /// Graphite accent in dark mode, yellows) where white would wash out.
    func foreground(in environment: EnvironmentValues) -> Color {
        let resolved = resolve(in: environment)
        let luminance = 0.2126 * Double(resolved.linearRed) + 0.7152 * Double(resolved.linearGreen) + 0.0722 * Double(resolved.linearBlue)
        return luminance > 0.45 ? Color(white: 0.08) : .white
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
    var tint: Color = .accent
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
