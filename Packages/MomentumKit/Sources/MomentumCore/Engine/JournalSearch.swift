import Foundation

/// A journal day a search found, with the words around the first match.
public struct JournalMatch: Identifiable, Hashable, Sendable {
    /// The part of the day the excerpt comes from.
    public enum Field: String, Sendable {
        case intention, win, reflection

        public var title: String {
            switch self {
            case .intention: "Intention"
            case .win: "Win"
            case .reflection: "Reflection"
            }
        }
    }

    public let entry: JournalEntry
    /// The first of the intention, win and reflection to hold one of the words.
    public let field: Field
    /// That field around its first match, on one line, cut where a word ends with "…" for what's
    /// left out, so a long reflection shows the sentence that matched rather than its opening.
    public let excerpt: String

    public var id: DayID { entry.day }
}

/// Finds journal days by the words written in them: a day matches when each word of the query is
/// somewhere in its intention, win or reflection, ignoring case and accents.
public struct JournalSearch: Sendable {
    /// The words to find, as typed.
    public let terms: [String]

    public init(_ query: String) {
        terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether there's nothing to search for.
    public var isEmpty: Bool { terms.isEmpty }

    /// The matching days, newest first.
    public func matches(in journal: [JournalEntry]) -> [JournalMatch] {
        guard !terms.isEmpty else { return [] }
        return journal.sorted { $0.day > $1.day }.compactMap(match)
    }

    /// Every place one of the words appears in `text`, in order, to emphasize them.
    public func ranges(in text: String) -> [Range<String.Index>] {
        terms.flatMap { Self.ranges(of: $0, in: text) }.sorted { $0.lowerBound < $1.lowerBound }
    }

    private func match(_ entry: JournalEntry) -> JournalMatch? {
        let fields: [(JournalMatch.Field, String)] = [(.intention, entry.intention), (.win, entry.win), (.reflection, entry.reflection)]
        let found = terms.allSatisfy { term in fields.contains { Self.find(term, in: $0.1) != nil } }
        guard found else { return nil }
        for (field, text) in fields {
            let first = terms.compactMap { Self.find($0, in: text) }.min { $0.lowerBound < $1.lowerBound }
            if let first {
                return JournalMatch(entry: entry, field: field, excerpt: Self.excerpt(of: text, around: first))
            }
        }
        return nil
    }

    private static var options: String.CompareOptions { [.caseInsensitive, .diacriticInsensitive] }

    private static func find(_ term: String, in text: String) -> Range<String.Index>? {
        text.range(of: term, options: options)
    }

    private static func ranges(of term: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex, let range = text.range(of: term, options: options, range: start..<text.endIndex), !range.isEmpty {
            found.append(range)
            start = range.upperBound
        }
        return found
    }

    /// `text` around `range`: up to `before` characters ahead of it and `after` behind it, cut
    /// between words, with "…" where text was left out, its lines and spaces joined into one line.
    static func excerpt(of text: String, around range: Range<String.Index>, before: Int = 40, after: Int = 80) -> String {
        var start = text.index(range.lowerBound, offsetBy: -before, limitedBy: text.startIndex) ?? text.startIndex
        var end = text.index(range.upperBound, offsetBy: after, limitedBy: text.endIndex) ?? text.endIndex
        if start > text.startIndex, let space = text[start..<range.lowerBound].firstIndex(where: \.isWhitespace) {
            start = text.index(after: space)
        }
        if end < text.endIndex, let space = text[range.upperBound..<end].lastIndex(where: \.isWhitespace) {
            end = space
        }
        let body = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let cutBefore = text[..<start].contains { !$0.isWhitespace }
        let cutAfter = text[end...].contains { !$0.isWhitespace }
        return (cutBefore ? "…" : "") + body + (cutAfter ? "…" : "")
    }
}
