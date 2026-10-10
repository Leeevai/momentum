import MomentumCore
import SwiftUI

/// The palettes as swatches of their aurora with the accent on top; the chosen one is ringed.
struct PalettePicker: View {
    @Environment(GoalStore.self) private var store
    var columns = 4

    var body: some View {
        let selected = store.data.preferences.palette
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 14) {
            ForEach(ThemePalette.allCases) { palette in
                Button {
                    store.updatePreferences { $0.palette = palette }
                } label: {
                    PaletteSwatch(palette: palette, isSelected: palette == selected)
                }
                .buttonStyle(.plain)
                .help(palette.summary)
                .accessibilityLabel("\(palette.title): \(palette.summary)")
                .accessibilityAddTraits(palette == selected ? .isSelected : [])
            }
        }
    }
}

private struct PaletteSwatch: View {
    let palette: ThemePalette
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = Color(palette.tokens(dark: colorScheme == .dark).accent)
        let shape = RoundedRectangle(cornerRadius: GlassTokens.controlRadius, style: .continuous)
        VStack(spacing: 6) {
            Aurora(animates: false, scale: 0.12)
                .environment(\.palette, Palette(palette))
                .overlay {
                    Circle()
                        .fill(accent)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                        .shadow(color: accent.opacity(0.4), radius: 4, y: 2)
                }
                .frame(height: 52)
                .clipShape(shape)
                .overlay(shape.strokeBorder(isSelected ? accent : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 1))
                .scaleEffect(isSelected ? 1 : 0.96)
            Text(palette.title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .animation(GlassTokens.motion, value: isSelected)
    }
}
