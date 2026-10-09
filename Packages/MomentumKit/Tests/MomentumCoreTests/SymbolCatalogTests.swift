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

    @Test("Achievement, journal and coach symbols exist")
    func featureSymbolsExist() {
        let goal = Goal(name: "Read", kind: .books, target: 1, books: [Book(title: "Dune", totalPages: 100, currentPage: 90, status: .reading)])
        var data = AppData(goals: [goal])
        data.log(1, for: goal.id, at: .now)
        let tips = ProgressEngine(data: data).coachTips(now: .now, limit: 20)
        let names = Achievement.all.map(\.symbol) + Achievement.Family.allCases.map(\.symbolName) + Mood.allCases.map(\.symbolName)
            + Energy.allCases.map(\.symbolName) + tips.map(\.symbol)
            + ["flame.fill", "square.stack.3d.up.fill", "gauge.with.dots.needle.33percent", "clock.fill", "arrow.up.forward.circle.fill",
               "arrow.down.forward.circle.fill", "hourglass.bottomhalf.filled", "book.fill", "exclamationmark.circle.fill", "flag.fill",
               "sun.horizon.fill", "moon.stars.fill"]
        for name in Set(names) {
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
