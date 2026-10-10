import MomentumCore
import SwiftUI

/// A glass banner that drops in from the top: an achievement earned, or a short message.
/// Dismisses itself; a click on an achievement opens Awards.
struct ToastBanner: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.self) private var environment
    let toast: Toast
    @State private var visible = false
    @State private var shine = false
    @State private var isDismissed = false

    var body: some View {
        VStack {
            if visible {
                Button(action: open) {
                    HStack(spacing: 14) {
                        icon
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eyebrow)
                                .font(.caption.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                            Text(title)
                                .font(.headline)
                            Text(detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 380, alignment: .leading)
                    .glassCard(tint: tint, cornerRadius: 24, padding: 14, highlighted: true)
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
                .transition(.move(edge: .top).combined(with: .scale(scale: 0.9)).combined(with: .opacity))
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height < 0 { hide() }
                })
            }
            Spacer()
        }
        .task(id: toast.id) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { visible = true }
            // A banner replaced or taken away is cancelled here, and must not go on to dismiss
            // whatever shows next.
            do {
                try await Task.sleep(for: .milliseconds(450))
                withAnimation(.easeInOut(duration: 1.2)) { shine = true }
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            hide()
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch toast.kind {
        case .achievement(let achievement):
            MedalView(achievement: achievement, size: 52)
                .rotation3DEffect(.degrees(shine ? 360 : 0), axis: (x: 0, y: 1, z: 0))
        case .achievements:
            Image(systemName: "trophy.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(GoalColor.yellow.tile))
                .symbolEffect(.bounce, value: shine)
        case .message(_, _, let symbol):
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accent.foreground(in: environment))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.accent.gradient))
        }
    }

    private var eyebrow: String {
        switch toast.kind {
        case .achievement(let achievement): "\(achievement.tier.title.uppercased()) AWARD"
        case .achievements: "AWARDS"
        case .message: "MOMENTUM"
        }
    }

    private var title: String {
        switch toast.kind {
        case .achievement(let achievement): achievement.title
        case .achievements(let count): "\(count) awards earned"
        case .message(let title, _, _): title
        }
    }

    private var detail: String {
        switch toast.kind {
        case .achievement(let achievement): achievement.detail
        case .achievements: "Everything you've done so far counts. Take a look."
        case .message(_, let detail, _): detail
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .achievement(let achievement): achievement.family.tint
        case .achievements: .award
        case .message: .accent
        }
    }

    private func open() {
        switch toast.kind {
        case .achievement, .achievements: store.route = .awards
        case .message: break
        }
        hide()
    }

    private func hide() {
        guard !isDismissed else { return }
        isDismissed = true
        withAnimation(.easeIn(duration: 0.25)) { visible = false }
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            store.dismissToast()
        }
    }
}
