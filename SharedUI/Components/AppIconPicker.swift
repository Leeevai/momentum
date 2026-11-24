import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// The app icons people can pick, drawn by scripts/make_icon.swift. Paper is the app's own icon.
/// On iPhone the others are alternate app icons (AppIcon-<name>), with their own dark and tinted
/// versions. On the Mac the choice is the Dock icon while Momentum runs: macOS can't change an
/// app's own icon without breaking its signature, so Finder keeps showing Paper.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case paper = "Paper"
    case midnight = "Midnight"
    case mono = "Mono"
    case ink = "Ink"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .paper: "The spiral on warm paper"
        case .midnight: "The spiral on black"
        case .mono: "A white spiral on black"
        case .ink: "A graphite spiral on paper"
        }
    }

    /// A square preview on iPhone; on the Mac, the icon already shaped for the Dock.
    var preview: Image { Image("AppIconChoice-\(rawValue)") }

    #if os(iOS)
    /// The alternate app icon's name, or nil for the app's own.
    var alternateIconName: String? { self == .paper ? nil : "AppIcon-\(rawValue)" }

    @MainActor static var current: AppIconChoice {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.alternateIconName == name } ?? .paper
    }
    #else
    private static let defaultsKey = "appIconChoice"

    @MainActor static var current: AppIconChoice {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppIconChoice.init(rawValue:)) ?? .paper
    }

    /// Sets the Dock icon to the saved choice: at launch, and whenever it changes.
    @MainActor static func applySaved() {
        let choice = current
        NSApplication.shared.applicationIconImage = choice == .paper ? nil : NSImage(named: "AppIconChoice-\(choice.rawValue)")
    }
    #endif

    /// Makes this the app's icon. Throws on iPhone if iOS refuses the change.
    @MainActor func choose() async throws {
        #if os(iOS)
        guard UIApplication.shared.supportsAlternateIcons else { return }
        try await UIApplication.shared.setAlternateIconName(alternateIconName)
        #else
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
        Self.applySaved()
        #endif
    }
}

/// The icon choices as tiles; tapping one makes it the app's icon. iOS confirms the change with
/// its own alert.
struct AppIconPicker: View {
    var columns = 4
    @State private var selection = AppIconChoice.current
    @State private var error: String?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 14) {
            ForEach(AppIconChoice.allCases) { choice in
                Button {
                    choose(choice)
                } label: {
                    AppIconTile(choice: choice, isSelected: choice == selection)
                }
                .buttonStyle(.plain)
                .help(choice.summary)
                .accessibilityLabel("\(choice.rawValue): \(choice.summary)")
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
        }
        .alert("Couldn't change the icon", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice != selection else { return }
        let previous = selection
        selection = choice
        Task {
            do {
                try await choice.choose()
            } catch {
                selection = previous
                self.error = error.localizedDescription
            }
        }
    }
}

private struct AppIconTile: View {
    let choice: AppIconChoice
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            icon
                .frame(width: 60, height: 60)
                .scaleEffect(isSelected ? 1 : 0.94)
                .accessibilityHidden(true)
            Text(choice.rawValue)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(GlassTokens.motion, value: isSelected)
    }

    /// The iPhone's previews are square, rounded here as the Home Screen does; the Mac's already
    /// have the macOS icon shape, with its margin.
    @ViewBuilder
    private var icon: some View {
        #if os(iOS)
        let shape = RoundedRectangle(cornerRadius: 13.5, style: .continuous)
        choice.preview
            .resizable()
            .clipShape(shape)
            .overlay(shape.strokeBorder(isSelected ? Color.accent : Color.primary.opacity(0.1), lineWidth: isSelected ? 2.5 : 1))
        #else
        choice.preview
            .resizable()
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 13.5, style: .continuous)
                        .strokeBorder(Color.accent, lineWidth: 2.5)
                        .padding(3)
                }
            }
        #endif
    }
}
