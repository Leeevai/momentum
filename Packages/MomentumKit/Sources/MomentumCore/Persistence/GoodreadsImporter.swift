import Foundation

/// Reads a Goodreads library export ("My Books" → Import and export → Export library).
public enum GoodreadsImporter {
    public enum ImportError: Error, Equatable {
        case notGoodreadsExport
    }

    /// Books from the export: shelves become statuses, and finish dates, ratings, page counts and
    /// links carry over. Books already in `existing` (same title and author) are skipped.
    public static func books(fromCSV text: String, existing: [Book] = [], now: Date = .now, calendar: Calendar = .current) throws -> [Book] {
        let rows = CSVParser.rows(text)
        guard let header = rows.first, header.contains("Title"), header.contains("Exclusive Shelf") else {
            throw ImportError.notGoodreadsExport
        }
        let column = Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func field(_ name: String, _ row: [String]) -> String {
            guard let index = column[name], index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var seen = Set(existing.map(key))
        var books: [Book] = []
        for row in rows.dropFirst() {
            let title = field("Title", row)
            guard !title.isEmpty else { continue }
            let added = date(field("Date Added", row), calendar: calendar) ?? now
            let read = date(field("Date Read", row), calendar: calendar)
            let pages = Int(field("Number of Pages", row)).flatMap { $0 > 0 ? $0 : nil }
            let rating = Int(field("My Rating", row)).flatMap { (1...5).contains($0) ? $0 : nil }
            let id = field("Book Id", row)
            var book = Book(
                title: title,
                author: field("Author", row),
                totalPages: pages,
                status: .wantToRead,
                rating: rating,
                link: id.isEmpty ? nil : URL(string: "https://www.goodreads.com/book/show/\(id)"),
                addedAt: added
            )
            switch field("Exclusive Shelf", row) {
            case "read":
                book.status = .finished
                book.finishedAt = read ?? added
                book.startedAt = book.finishedAt
                book.currentPage = pages ?? 0
            case "currently-reading":
                book.status = .reading
                book.startedAt = added
            default:
                book.status = .wantToRead
            }
            guard seen.insert(key(book)).inserted else { continue }
            books.append(book)
        }
        return books
    }

    private static func key(_ book: Book) -> String {
        "\(book.title.lowercased())|\(book.author.lowercased())"
    }

    /// Goodreads writes dates as "2024/05/14", in the Gregorian calendar whatever the device uses:
    /// read in a Buddhist or Japanese calendar, the year would land centuries away. Noon in
    /// `calendar`'s time zone, clear of any daylight-saving change.
    static func date(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

/// A small RFC 4180 reader: quoted fields may contain commas, doubled quotes and line breaks.
enum CSVParser {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var characters = Array(text).makeIterator()
        var pending: Character?
        while let character = pending ?? characters.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = characters.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                inQuotes = true
            case ",":
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
