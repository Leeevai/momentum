import Foundation

/// Flattens the log into a spreadsheet-friendly CSV, one row per entry.
public enum CSVExporter {
    public static let header = ["date", "goal", "category", "kind", "amount", "unit", "display_amount", "source", "book", "note"]

    public static func csv(for data: AppData) -> String {
        let goals = Dictionary(data.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let dateFormat = Date.ISO8601FormatStyle(timeZone: .current)
        var lines = [header.joined(separator: ",")]
        for entry in data.entries.sorted(by: { $0.date < $1.date }) {
            guard let goal = goals[entry.goalID] else { continue }
            let book = entry.bookID.flatMap { id in goal.books.first { $0.id == id }?.title } ?? ""
            let amount = goal.kind == .time ? entry.amount / 60 : entry.amount
            let unit = goal.kind == .time ? "minutes" : (goal.kind == .books ? "pages" : goal.displayUnit)
            let display = goal.kind == .books ? "\(Formatting.number(entry.amount)) pages" : goal.format(entry.amount)
            let row = [
                entry.date.formatted(dateFormat),
                goal.name,
                goal.category,
                goal.kind.rawValue,
                String(format: "%.2f", amount),
                unit,
                display,
                entry.source.rawValue,
                book,
                entry.note,
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quotes a field when it holds a comma, quote or newline, doubling inner quotes (RFC 4180).
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
