import MomentumCore
import SwiftUI

/// Makes or edits a custom palette: an accent, a background tint, goal colors in a harmony and a
/// feel for lightness and contrast, previewed live in light and dark. Saving draws in it.
struct PaletteEditor: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    @State private var draft: CustomPalette
    @State private var confirmingDelete = false

    init(palette: CustomPalette, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: palette)
    }

    var body: some View {
        let palette = Palette(draft)
        VStack(spacing: 0) {
            PalettePreview(palette: palette)
                .padding(16)
            Form {
                nameSection
                accentSection
                backgroundSection
                goalColorSection
                feelSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            footer(palette)
        }
        .sheetFrame(width: 600, height: 760)
        .background(Aurora(animates: false).palette(palette))
        .confirmationDialog("Delete \(draft.displayName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Palette", role: .destructive) {
                store.updatePreferences { $0.deleteCustomPalette(draft.id) }
                dismiss()
            }
        } message: {
            Text("If it's in use, the built-in palette closest to it takes over.")
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            TextField("Name", text: $draft.name, prompt: Text("e.g. Harbor"))
        }
    }

    private var accentSection: some View {
        Section {
            HueSlider(title: "Hue", hue: $draft.recipe.accentHue)
            LevelSlider(title: "Vividness", value: $draft.recipe.accentVividness, low: "Ink", high: "Vivid")
        } header: {
            Text("Accent")
        } footer: {
            Text("Buttons, selection and links. With no vividness it's ink in light mode and paper in dark.")
        }
    }

    private var backgroundSection: some View {
        Section {
            HueSlider(title: "Hue", hue: $draft.recipe.backgroundHue)
            LevelSlider(title: "Tint", value: $draft.recipe.backgroundTint, low: "Faint", high: "Rich")
        } header: {
            Text("Background")
        } footer: {
            Text("The aurora drifting behind every screen.")
        }
    }

    private var goalColorSection: some View {
        Section {
            Picker("Harmony", selection: $draft.recipe.harmony) {
                ForEach(PaletteHarmony.allCases) { harmony in
                    Text(harmony.title).tag(harmony)
                }
            }
            HueSlider(title: "Base hue", hue: $draft.recipe.swatchHue)
            LevelSlider(title: "Vividness", value: $draft.recipe.swatchVividness, low: "Muted", high: "Vivid")
        } header: {
            Text("Goal colors")
        } footer: {
            Text("\(draft.recipe.harmony.summary). Each goal keeps its color's place in the palette.")
        }
    }

    private var feelSection: some View {
        Section {
            LevelSlider(title: "Lightness", value: $draft.recipe.lightness, low: "Deeper", high: "Lighter")
            LevelSlider(title: "Contrast", value: $draft.recipe.contrast, low: "Soft", high: "Crisp")
        } header: {
            Text("Feel")
        } footer: {
            Text("Text on every color stays legible, whatever you choose.")
        }
    }

    private func footer(_ palette: Palette) -> some View {
        HStack {
            if !isNew {
                Button("Delete", role: .destructive) { confirmingDelete = true }
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Add Palette" : "Save") {
                store.updatePreferences { $0.choose(draft) }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .primaryActionStyle(palette.colors.accent)
        }
        .padding(16)
        .background(.bar)
    }
}

// MARK: - Preview

/// A palette drawn small in light and dark: the aurora, a glass pane with a goal's icon, its
/// ring and the accent's button, and every goal color.
struct PalettePreview: View {
    let palette: Palette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                pane(.light)
                pane(.dark)
            }
            VStack(spacing: 12) {
                pane(.light)
                pane(.dark)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of \(palette.title) in light and dark")
    }

    private func pane(_ scheme: ColorScheme) -> some View {
        PalettePreviewPane()
            .palette(palette)
            .environment(\.colorScheme, scheme)
    }
}

private struct PalettePreviewPane: View {
    @Environment(\.palette) private var palette

    /// Goals drawn in the preview, one per kind of color use: a tile, rings, a bar.
    private static let goal = Goal(name: "Deep work", symbol: "laptopcomputer", color: .blue, target: 3600)
    private static let rings: [(GoalColor, Double)] = [(.blue, 0.8), (.green, 0.55), (.orange, 1), (.purple, 0.3)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                GoalIcon(goal: Self.goal, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.goal.name)
                        .font(.subheadline.weight(.semibold))
                    ProgressBar(progress: 0.65, color: .blue, height: 5)
                }
                Button("Start") {}
                    .primaryActionStyle(palette.colors.accent, compact: true)
            }
            HStack(spacing: 8) {
                ForEach(Self.rings, id: \.0) { ring in
                    ProgressRing(progress: ring.1, color: ring.0, lineWidth: 5)
                        .frame(width: 30, height: 30)
                }
                Spacer(minLength: 0)
                StreakBadge(count: 12)
            }
            SwatchRow()
        }
        .glassCard(cornerRadius: 18, padding: 12)
        .padding(10)
        .frame(minWidth: 256)
        .background(Aurora(animates: false, scale: 0.4))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Every goal color of the palette in the environment, in order.
private struct SwatchRow: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(GoalColor.allCases) { color in
                Circle()
                    .fill(palette.color(color))
                    .frame(width: 14, height: 14)
            }
        }
    }
}

// MARK: - Controls

/// A hue from 0 to 359 degrees, over a strip of the wheel, with the chosen color beside it.
private struct HueSlider: View {
    let title: String
    @Binding var hue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Circle()
                    .fill(Color(OKLCH(0.7, 0.12, hue).inSRGB))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            }
            Slider(value: $hue, in: 0...359) {
                Text(title)
            }
            .labelsHidden()
            .accessibilityValue("\(Int(hue.rounded())) degrees")
            HueStrip()
                .frame(height: 4)
                .accessibilityHidden(true)
        }
    }
}

/// The color wheel as a strip, in the same lightness throughout, under a hue slider.
private struct HueStrip: View {
    private static let colors: [Color] = stride(from: 0.0, through: 360, by: 30).map { Color(OKLCH(0.72, 0.12, $0).inSRGB) }

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: Self.colors, startPoint: .leading, endPoint: .trailing))
            .padding(.horizontal, 2)
    }
}

/// A level from 0 to 1 between two named ends, stacked so it fits at phone width.
private struct LevelSlider: View {
    let title: String
    @Binding var value: Double
    let low: String
    let high: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            HStack(spacing: 10) {
                Text(low)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $value, in: 0...1) {
                    Text(title)
                }
                .labelsHidden()
                .accessibilityValue("\(Int((value * 100).rounded())) percent, from \(low) to \(high)")
                Text(high)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
