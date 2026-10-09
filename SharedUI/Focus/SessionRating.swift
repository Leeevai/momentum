import MomentumCore
import SwiftUI

/// A finished focus session waiting for its one-tap rating.
struct SessionRating: Identifiable, Equatable {
    let id = UUID()
    let goal: Goal
    let entryIDs: Set<UUID>
    let seconds: Double
    let endedAt = Date()

    /// Sessions shorter than this aren't asked about.
    static let minimumSeconds: Double = 5 * 60
    /// How long the question waits before it goes away by itself.
    static let lifetime: Duration = .seconds(20)
}

extension FocusQuality {
    var tint: Color {
        switch self {
        case .scattered: .orange
        case .steady: .teal
        case .flow: .indigo
        }
    }
}

/// "How did it go?" with three answers, after a focus session ends.
struct SessionRatingBanner: View {
    @Environment(GoalStore.self) private var store
    let rating: SessionRating
    @State private var chosen: FocusQuality?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GoalIcon(goal: rating.goal, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(chosen == nil ? "How did it go?" : "Noted")
                        .font(.headline)
                        .contentTransition(.opacity)
                    Text("\(Formatting.duration(rating.seconds)) of \(rating.goal.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(CircleButtonStyle(tint: .secondary, size: 26, prominent: false))
                .accessibilityLabel("Not now")
            }
            HStack(spacing: 8) {
                ForEach(FocusQuality.allCases) { quality in
                    answer(quality)
                }
            }
        }
        .frame(maxWidth: 420)
        .glassCard(tint: chosen?.tint ?? rating.goal.tint, padding: 14)
        // Solid enough to read over whatever is underneath, and lifted off it.
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.regularMaterial))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(.horizontal, 16)
        .task(id: rating.id) {
            try? await Task.sleep(for: SessionRating.lifetime)
            dismiss()
        }
    }

    private func answer(_ quality: FocusQuality) -> some View {
        let isChosen = chosen == quality
        return Button {
            choose(quality)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: quality.symbolName)
                    .font(.title3)
                    .symbolEffect(.bounce, value: isChosen)
                Text(quality.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(quality.tint)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(quality.tint.opacity(isChosen ? 0.3 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(quality.tint.opacity(isChosen ? 0.6 : 0), lineWidth: 1.5)
            )
            .scaleEffect(isChosen ? 1.04 : 1)
            .opacity(chosen == nil || isChosen ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(chosen != nil)
        .help(quality.detail)
        .accessibilityLabel("\(quality.title): \(quality.detail)")
    }

    private func choose(_ quality: FocusQuality) {
        withAnimation(.snappy) { chosen = quality }
        store.rate(rating, as: quality)
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            dismiss()
        }
    }

    private func dismiss() {
        guard store.sessionRating?.id == rating.id else { return }
        withAnimation(.spring(duration: 0.4)) { store.sessionRating = nil }
    }
}

extension View {
    /// Shows the session question at the bottom, raised by `bottomInset` (above a tab bar).
    func sessionRatingOverlay(_ store: GoalStore, bottomInset: CGFloat) -> some View {
        overlay(alignment: .bottom) {
            if let rating = store.sessionRating {
                SessionRatingBanner(rating: rating)
                    .padding(.bottom, bottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(rating.id)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: store.sessionRating?.id)
    }
}
