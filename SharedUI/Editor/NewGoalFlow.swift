import MomentumCore
import SwiftUI

/// New goal: pick a template (or start blank), then fine-tune it in the editor.
struct NewGoalFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Goal?

    var body: some View {
        if let draft {
            GoalEditor(goal: draft, isNew: true, onBack: { withAnimation { self.draft = nil } })
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            TemplateGallery { goal in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { draft = goal }
            } onCancel: {
                dismiss()
            }
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }
}

private struct TemplateGallery: View {
    var onPick: (Goal) -> Void
    var onCancel: () -> Void

    /// The kinds people reach for most come first.
    static let galleryOrder: [GoalKind] = [.time, .books, .count, .amount, .milestones]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New goal")
                    .font(.title.weight(.bold))
                Text("Start from a template, or build your own from scratch.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button {
                        onPick(Goal(name: "", symbol: "target", color: .blue, kind: .time, period: .daily, target: 30 * 60))
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.accent.opacity(0.15)))
                                .foregroundStyle(Color.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Blank goal").font(.headline)
                                Text("Time, count, amount, books or milestones: you choose.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .glassCard(tint: .accent, padding: 14)
                    }
                    .buttonStyle(.plain)

                    ForEach(Self.galleryOrder) { kind in
                        let templates = GoalTemplate.all.filter { $0.prototype.kind == kind }
                        if !templates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(kind.title, systemImage: kind.symbolName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                                    ForEach(templates) { template in
                                        Button { onPick(template.makeGoal()) } label: {
                                            TemplateTile(template: template)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding([.horizontal, .bottom], 24)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .sheetFrame(width: 640, height: 620)
    }
}

struct TemplateTile: View {
    let template: GoalTemplate
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let goal = template.prototype
        HStack(spacing: 12) {
            GoalIcon(goal: goal, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(goal.tint.opacity(isHovered ? 0.16 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(goal.tint.opacity(isHovered ? 0.45 : 0.15), lineWidth: 1))
        .scaleEffect(isHovered && !reduceMotion ? 1.02 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
