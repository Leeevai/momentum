import Foundation

/// A book found in the Open Library catalog.
public struct BookSearchResult: Identifiable, Hashable, Sendable {
    /// The Open Library work key, such as "/works/OL893415W".
    public var id: String
    public var title: String
    public var author: String
    public var pages: Int?
    public var year: Int?
    public var coverURL: URL?
    public var link: URL

    /// A reading-list entry pre-filled from the result.
    public func makeBook(status: BookStatus = .wantToRead, at now: Date = .now) -> Book {
        Book(title: title, author: author, totalPages: pages, status: status, link: link, coverURL: coverURL, addedAt: now)
    }
}

/// Searches the Open Library catalog (openlibrary.org): free, no account, no API key.
///
/// The only network request Momentum makes, and only when someone types a book search.
public enum OpenLibrary {
    private static let fields = "key,title,author_name,number_of_pages_median,first_publish_year,cover_i"

    public static func searchURL(for query: String, limit: Int = 12) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "fields", value: fields),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return components?.url
    }

    public static func search(_ query: String, session: URLSession = .shared) async throws -> [BookSearchResult] {
        guard let url = searchURL(for: query) else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Momentum (https://github.com/Leeevai/momentum)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try parse(data)
    }

    /// Turns a search response into results, skipping entries without a title.
    public static func parse(_ data: Data) throws -> [BookSearchResult] {
        struct Response: Decodable {
            struct Doc: Decodable {
                var key: String?
                var title: String?
                var author_name: [String]?
                var number_of_pages_median: Int?
                var first_publish_year: Int?
                var cover_i: Int?
            }
            var docs: [Doc]
        }
        return try JSONDecoder().decode(Response.self, from: data).docs.compactMap { doc in
            guard let key = doc.key, let title = doc.title, !title.isEmpty,
                  let link = URL(string: "https://openlibrary.org\(key)") else { return nil }
            return BookSearchResult(
                id: key,
                title: title,
                author: (doc.author_name ?? []).prefix(2).joined(separator: ", "),
                pages: doc.number_of_pages_median,
                year: doc.first_publish_year,
                coverURL: doc.cover_i.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-M.jpg") },
                link: link
            )
        }
    }
}
