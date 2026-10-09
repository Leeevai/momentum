import MomentumCore
import SwiftUI
import UniformTypeIdentifiers

/// A books goal's library: reading now, up next, finished, with quick status changes.
struct BooksSection: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    @State private var importMessage: String?

    var body: some View {
        let reading = goal.books.filter { $0.status == .reading }
        let queue = goal.books.filter { $0.status == .wantToRead }
        let finished = goal.books.filter { $0.status == .finished }.sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }
        let abandoned = goal.books.filter { $0.status == .abandoned }

        VStack(alignment: .leading, spacing: 16) {
            SectionTitle("Library", systemImage: "books.vertical", trailing: AnyView(
                HStack(spacing: 8) {
                    Button(action: importFromGoodreads) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PillButtonStyle(tint: goal.tint, prominent: false, compact: true))
                    .help("Import a Goodreads library export (CSV)")
                    Button {
                        store.sheet = .book(goalID: goal.id, book: nil)
                    } label: {
                        Label("Add book", systemImage: "plus")
                    }
                    .buttonStyle(PillButtonStyle(tint: goal.tint, prominent: false, compact: true))
                }
            ))
            if let importMessage {
                Label(importMessage, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if goal.books.isEmpty {
                Text("Your reading list is empty. Add the books you're reading and the ones you want to read next, or import your Goodreads library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            shelf("Reading", books: reading)
            shelf("Up next", books: queue)
            shelf("Finished", books: finished)
            shelf("Set aside", books: abandoned)
        }
        .glassCard(tint: goal.tint)
    }

    /// Goodreads: My Books → Import and export → Export library, then pick the CSV here.
    private func importFromGoodreads() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.prompt = "Import"
        panel.message = "Choose the goodreads_library_export.csv file from Goodreads."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let books = try GoodreadsImporter.books(fromCSV: text, existing: goal.books)
            guard !books.isEmpty else {
                importMessage = "Every book in that file is already in your library."
                return
            }
            store.perform("Import Books") { data in
                for book in books { data.upsertBook(book, in: goal.id) }
            }
            let finished = books.filter { $0.status == .finished }.count
            importMessage = "Imported \(books.count) \(books.count == 1 ? "book" : "books") (\(finished) finished). Undo with ⌘Z."
        } catch GoodreadsImporter.ImportError.notGoodreadsExport {
            importMessage = "That file isn't a Goodreads library export."
        } catch {
            importMessage = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func shelf(_ title: String, books: [Book]) -> some View {
        if !books.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(title) · \(books.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(books) { book in
                        BookRow(goal: goal, book: book)
                    }
                }
            }
        }
    }
}

private struct BookRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let book: Book
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BookCover(book: book, tint: goal.tint, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                switch book.status {
                case .reading:
                    if let fraction = book.fraction {
                        ProgressBar(progress: fraction, color: goal.color, height: 4)
                            .frame(maxWidth: 160)
                    }
                    Text(book.totalPages.map { "p. \(book.currentPage) of \($0)" } ?? "p. \(book.currentPage)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                case .finished:
                    HStack(spacing: 4) {
                        StarRating(rating: book.rating ?? 0, tint: .yellow) { stars in
                            var updated = book
                            updated.rating = stars
                            store.perform("Rate Book") { $0.upsertBook(updated, in: goal.id) }
                        }
                        if let finished = book.finishedAt {
                            Text(finished, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                case .wantToRead, .abandoned:
                    if let pages = book.totalPages {
                        Text("\(pages) pages").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if isHovered {
                actionButton
                    .transition(.opacity)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(isHovered ? 0.06 : 0.03)))
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering } }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.sheet = .book(goalID: goal.id, book: book) }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch book.status {
        case .wantToRead, .abandoned:
            Button("Start") { store.perform("Start Book") { $0.startReading(book.id, in: goal.id) } }
                .buttonStyle(PillButtonStyle(tint: goal.tint, prominent: false, compact: true))
        case .reading:
            Button("+\(Int(goal.quickAddStep))") {
                store.perform("Log Pages") { $0.logPages(Int(goal.quickAddStep), in: book.id, of: goal.id) }
            }
            .buttonStyle(PillButtonStyle(tint: goal.tint, compact: true))
            .help("Log \(Int(goal.quickAddStep)) pages")
        case .finished:
            EmptyView()
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Edit…") { store.sheet = .book(goalID: goal.id, book: book) }
        if let link = book.link {
            Button("Open Link") { NSWorkspace.shared.open(link) }
        }
        Divider()
        if book.status != .reading {
            Button(book.status == .finished ? "Read Again" : "Start Reading") {
                store.perform("Start Book") { $0.startReading(book.id, in: goal.id) }
            }
        }
        if book.status != .finished {
            Button("Mark as Finished") { store.perform("Finish Book") { $0.finishBook(book.id, in: goal.id) } }
        }
        if book.status == .reading {
            Button("Set Aside") { store.perform("Set Book Aside") { $0.abandonBook(book.id, in: goal.id) } }
        }
        Divider()
        Button("Remove", role: .destructive) {
            store.perform("Remove Book") { $0.removeBook(book.id, from: goal.id) }
        }
    }
}

/// A book's cover: the catalog image when there is one, otherwise a generated cover with the
/// title's initials on a color picked from the title.
struct BookCover: View {
    let book: Book
    let tint: Color
    var height: CGFloat = 60

    var body: some View {
        Group {
            if let url = book.coverURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        generated
                    }
                }
            } else {
                generated
            }
        }
        .frame(width: height * 0.68, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(.black.opacity(0.18)).frame(width: 3)
        }
        .shadow(color: .black.opacity(0.2), radius: 2, x: 1, y: 2)
        .opacity(book.status == .abandoned ? 0.5 : 1)
    }

    private var generated: some View {
        let palette: [Color] = [.indigo, .teal, .orange, .pink, .purple, .brown, .blue, .green, .red, .mint]
        let seed = book.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let color = palette[seed % palette.count]
        let initials = book.title.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return LinearGradient(colors: [color.blended(with: .white, by: 0.2), color.blended(with: .black, by: 0.25)], startPoint: .top, endPoint: .bottom)
            .overlay {
                Text(initials.uppercased())
                    .font(.system(size: height * 0.26, weight: .bold, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
            }
    }
}

struct StarRating: View {
    let rating: Int
    var tint: Color = .yellow
    var onChange: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundStyle(star <= rating ? tint : Color.secondary.opacity(0.5))
                    .onTapGesture { onChange?(star == rating ? 0 : star) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating) of 5 stars")
    }
}
