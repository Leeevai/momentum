import MomentumCore
import SwiftUI

/// The palettes as swatches of their aurora with the accent and a few goal colors on top; the
/// chosen one is ringed. The built-in palettes come first, then the ones made here, and a tile
/// to make another.
struct PalettePicker: View {
    @Environment(GoalStore.self) private var store
    var columns = 4
    @State private var editing: PaletteEdit?
    @State private var deleting: CustomPalette?

    var body: some View {
        let preferences = store.data.preferences
        let activeCustom = preferences.activeCustomPalette?.id
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: grid, spacing: 14) {
                ForEach(ThemePalette.allCases) { palette in
                    builtInTile(palette, isSelected: activeCustom == nil && preferences.palette == palette)
                }
            }
            Text("Your palettes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: grid, spacing: 14) {
                ForEach(preferences.customPalettes) { palette in
                    customTile(palette, isSelected: palette.id == activeCustom)
                }
                Button {
                    editing = PaletteEdit(palette: newPalette(), isNew: true)
                } label: {
                    NewPaletteTile()
                }
                .buttonStyle(.plain)
                .help("Make a palette of your own, starting from this one")
            }
        }
        .sheet(item: $editing) { edit in
            PaletteEditor(palette: edit.palette, isNew: edit.isNew)
        }
        .confirmationDialog("Delete \(deleting?.displayName ?? "this palette")?", isPresented: isDeleting, titleVisibility: .visible) {
            Button("Delete Palette", role: .destructive) {
                if let deleting { store.updatePreferences { $0.deleteCustomPalette(deleting.id) } }
            }
        } message: {
            Text("If it's in use, the built-in palette closest to it takes over.")
        }
    }

    private var grid: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func builtInTile(_ palette: ThemePalette, isSelected: Bool) -> some View {
        Button {
            store.updatePreferences { $0.choose(palette) }
        } label: {
            PaletteSwatch(palette: Palette(palette), isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(palette.summary)
        .accessibilityLabel("\(palette.title): \(palette.summary)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Customize…", systemImage: "slider.horizontal.3") {
                editing = PaletteEdit(palette: CustomPalette(name: "My \(palette.title)", recipe: palette.recipe), isNew: true)
            }
        }
    }

    private func customTile(_ palette: CustomPalette, isSelected: Bool) -> some View {
        Button {
            // A second tap on the palette in use opens it to edit.
            if isSelected {
                editing = PaletteEdit(palette: palette, isNew: false)
            } else {
                store.updatePreferences { $0.choose(palette) }
            }
        } label: {
            PaletteSwatch(palette: Palette(palette), isSelected: isSelected, isEditable: true)
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Edit \(palette.displayName)" : palette.displayName)
        .accessibilityLabel(palette.displayName)
        .accessibilityHint(isSelected ? "Edits the palette" : "Draws the app in this palette")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Edit…", systemImage: "slider.horizontal.3") {
                editing = PaletteEdit(palette: palette, isNew: false)
            }
            Button("Duplicate", systemImage: "plus.square.on.square") {
                store.updatePreferences { $0.save(CustomPalette(name: "\(palette.displayName) copy", recipe: palette.recipe)) }
            }
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) {
                deleting = palette
            }
        }
    }

    /// A new palette starts from the one in use.
    private func newPalette() -> CustomPalette {
        let preferences = store.data.preferences
        if let custom = preferences.activeCustomPalette {
            return CustomPalette(name: "\(custom.displayName) copy", recipe: custom.recipe)
        }
        return CustomPalette(name: "My \(preferences.palette.title)", recipe: preferences.palette.recipe)
    }
}

/// A palette being made or edited in the sheet.
private struct PaletteEdit: Identifiable {
    let palette: CustomPalette
    let isNew: Bool
    var id: UUID { palette.id }
}

/// A palette's aurora with its accent in the middle and a row of its goal colors beneath.
struct PaletteSwatch: View {
    let palette: Palette
    let isSelected: Bool
    var isEditable = false

    var body: some View {
        VStack(spacing: 6) {
            PaletteSwatchCard(isSelected: isSelected, isEditable: isEditable)
                .palette(palette)
            Text(palette.title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .animation(GlassTokens.motion, value: isSelected)
    }
}

private struct PaletteSwatchCard: View {
    let isSelected: Bool
    let isEditable: Bool
    @Environment(\.palette) private var palette

    /// Goal colors that show a palette's range at a glance.
    private static let sample: [GoalColor] = [.blue, .green, .orange, .purple, .teal]

    var body: some View {
        let accent = palette.colors.accent
        let shape = RoundedRectangle(cornerRadius: GlassTokens.controlRadius, style: .continuous)
        Aurora(animates: false, scale: 0.12)
            .overlay {
                VStack(spacing: 7) {
                    Circle()
                        .fill(accent)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                        .shadow(color: accent.opacity(0.4), radius: 4, y: 2)
                    HStack(spacing: 3) {
                        ForEach(Self.sample, id: \.self) { color in
                            Circle()
                                .fill(palette.color(color))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected && isEditable {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                }
            }
            .frame(height: 60)
            .clipShape(shape)
            .overlay(shape.strokeBorder(isSelected ? accent : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 1))
            .scaleEffect(isSelected ? 1 : 0.96)
            .accessibilityHidden(true)
    }
}

/// The tile that makes a new palette.
private struct NewPaletteTile: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GlassTokens.controlRadius, style: .continuous)
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(shape.fill(Color.primary.opacity(0.04)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .scaleEffect(0.96)
            Text("New")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New palette")
    }
}
