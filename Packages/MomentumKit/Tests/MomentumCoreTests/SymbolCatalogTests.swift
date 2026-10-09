import Foundation
import Testing
@testable import MomentumCore
#if canImport(AppKit)
import AppKit
#endif

@Suite("Symbols")
struct SymbolCatalogTests {
    #if canImport(AppKit)
    @Test("Every catalog symbol, default and emoji match is a real SF Symbol")
    func symbolsExist() {
        let mapped = ["🎯", "💻", "📚", "🏃", "🧘", "💧", "🇪🇸", "🏋🏽", "✍️"].compactMap(SymbolCatalog.symbol(forEmoji:))
        let defaults = GoalKind.allCases.map(SymbolCatalog.defaultSymbol(for:))
        let templates = GoalTemplate.all.map(\.prototype.symbol)
        for name in Set(SymbolCatalog.all + mapped + defaults + templates) {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name) is not an SF Symbol")
        }
    }
    #endif

    @Test("No symbol appears twice in the picker")
    func noDuplicates() {
        #expect(Set(SymbolCatalog.all).count == SymbolCatalog.all.count)
    }

    @Test("Emoji icons from earlier versions map to symbols, including flags and skin tones")
    func emojiMigration() {
        #expect(SymbolCatalog.symbol(forEmoji: "📚") == "books.vertical.fill")
        #expect(SymbolCatalog.symbol(forEmoji: "🇪🇸") == "character.bubble.fill")
        #expect(SymbolCatalog.symbol(forEmoji: "🏋🏽") == "figure.strengthtraining.traditional")
        #expect(SymbolCatalog.symbol(forEmoji: "✍️") == "pencil.and.scribble")
        #expect(SymbolCatalog.symbol(forEmoji: "🦄") == nil)
    }

    @Test("Goals saved before symbols decode with a matching symbol")
    func decodesLegacyIcon() throws {
        let json = #"{"version": 2, "goals": [{"name": "Gym", "icon": "💪", "kind": "count", "target": 1}, {"name": "Odd", "icon": "🦄", "kind": "books", "target": 1}]}"#
        let goals = try FileStore.decode(Data(json.utf8)).goals
        #expect(goals.map(\.symbol) == ["dumbbell.fill", "books.vertical.fill"])
    }
}
