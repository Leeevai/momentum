import MomentumCore
import SwiftUI

/// The goal's icon in the editor: its tile, which opens the symbol picker.
struct SymbolPickerButton: View {
    @Binding var goal: Goal
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 10) {
                GoalIcon(goal: goal, size: 30)
                Text("Choose icon…")
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SymbolPicker(selection: $goal.symbol, color: goal.color) { isPresented = false }
        }
    }
}

/// A searchable grid of SF Symbols, grouped like the catalog.
struct SymbolPicker: View {
    @Binding var selection: String
    let color: GoalColor
    var onPick: () -> Void
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 6)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search icons", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    SymbolCell(symbol: symbol, color: color, isSelected: symbol == selection) {
                                        selection = symbol
                                        onPick()
                                    }
                                }
                            }
                        }
                    }
                    if groups.isEmpty {
                        Text("No icon matches \"\(query)\".")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                }
                .padding(12)
            }
        }
        .sheetFrame(width: 400, height: 420)
        .onAppear { searchFocused = true }
    }

    /// Groups narrowed by the query, matching words of the symbol's name ("figure run").
    private var groups: [SymbolCatalog.Group] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return SymbolCatalog.groups }
        return SymbolCatalog.groups.compactMap { group in
            let matches = group.symbols.filter { symbol in
                let name = symbol.replacingOccurrences(of: ".", with: " ")
                return words.allSatisfy { name.contains($0) || group.name.lowercased().contains($0) }
            }
            return matches.isEmpty ? nil : SymbolCatalog.Group(name: group.name, symbols: matches)
        }
    }
}

private struct SymbolCell: View {
    let symbol: String
    let color: GoalColor
    let isSelected: Bool
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(color.color))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(color.linear) : AnyShapeStyle(color.color.opacity(isHovered ? 0.16 : 0.07)))
                )
                .scaleEffect(isHovered && !isSelected ? 1.06 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(symbol)
        .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
    }
}
