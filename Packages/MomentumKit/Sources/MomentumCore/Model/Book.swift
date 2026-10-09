import Foundation

public enum BookStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case wantToRead
    case reading
    case finished
    case abandoned

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wantToRead: "Want to read"
        case .reading: "Reading"
        case .finished: "Finished"
        case .abandoned: "Abandoned"
        }
    }

    public var symbolName: String {
        switch self {
        case .wantToRead: "bookmark"
        case .reading: "book"
        case .finished: "checkmark.seal"
        case .abandoned: "xmark.circle"
        }
    }
}

/// A book on a books goal's reading list.
public struct Book: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var author: String
    /// Total page count, when known; enables a progress bar and auto-finishing.
    public var totalPages: Int?
    public var currentPage: Int
    public var status: BookStatus
    /// 1 to 5 stars, set once finished.
    public var rating: Int?
    public var notes: String
    /// A store, Goodreads, or ebook link.
    public var link: URL?
    /// A cover image, when the book came from a catalog search.
    public var coverURL: URL?
    public var addedAt: Date
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        totalPages: Int? = nil,
        currentPage: Int = 0,
        status: BookStatus = .wantToRead,
        rating: Int? = nil,
        notes: String = "",
        link: URL? = nil,
        coverURL: URL? = nil,
        addedAt: Date = .now,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.totalPages = totalPages
        self.currentPage = currentPage
        self.status = status
        self.rating = rating
        self.notes = notes
        self.link = link
        self.coverURL = coverURL
        self.addedAt = addedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    /// Share of pages read, when the page count is known.
    public var fraction: Double? {
        guard let totalPages, totalPages > 0 else { return status == .finished ? 1 : nil }
        return min(1, Double(currentPage) / Double(totalPages))
    }

    public var pagesLeft: Int? {
        totalPages.map { max(0, $0 - currentPage) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, author, totalPages, currentPage, status, rating, notes, link, coverURL, addedAt, startedAt, finishedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(.id, default: UUID())
        title = try c.decode(.title, default: "Untitled")
        author = try c.decode(.author, default: "")
        totalPages = try c.decodeIfPresent(Int.self, forKey: .totalPages)
        currentPage = try c.decode(.currentPage, default: 0)
        status = try c.decode(.status, default: .wantToRead)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        notes = try c.decode(.notes, default: "")
        link = try c.decodeIfPresent(URL.self, forKey: .link)
        coverURL = try c.decodeIfPresent(URL.self, forKey: .coverURL)
        addedAt = try c.decode(.addedAt, default: .now)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
    }
}
