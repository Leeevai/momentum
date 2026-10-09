import AppKit
import MomentumCore
import SwiftUI
import UniformTypeIdentifiers

/// Log an amount at a chosen time, with a note: forgotten sessions, past workouts, words written.
/// With an existing entry, edits it instead.
struct LogProgressSheet: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    let entry: LogEntry?
    @State private var amount: Double
    @State private var minutes: Int
    /// The minutes shown when the sheet opened: unchanged means keep the entry's exact amount.
    private let initialMinutes: Int
    @State private var date: Date
    @State private var note: String

    /// `day` presets the date to that day (at the current time of day, or noon for today's future),
    /// for logging a day that was missed.
    init(goal: Goal, entry: LogEntry? = nil, day: Date? = nil) {
        self.goal = goal
        self.entry = entry
        let value = entry?.amount ?? goal.quickAddStep
        _amount = State(initialValue: value)
        let wholeMinutes = Int((abs(value) / 60).rounded())
        let shownMinutes = value < 0 ? -max(1, wholeMinutes) : max(1, wholeMinutes)
        _minutes = State(initialValue: shownMinutes)
        initialMinutes = shownMinutes
        _date = State(initialValue: entry?.date ?? day.map(Self.moment(on:)) ?? .now)
        _note = State(initialValue: entry?.note ?? "")
    }

    /// The current time of day on `day`, kept in the past.
    private static func moment(on day: Date) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: .now)
        let moment = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
        return min(moment, .now)
    }

    /// Page logs move a book's bookmark, so their amount is fixed once logged.
    private var amountIsLocked: Bool { entry?.bookID != nil }

    /// Editing a correction (a negative entry) keeps it negative.
    private var isCorrection: Bool { (entry?.amount ?? 0) < 0 }

    /// The amount to save: the entry's exact amount unless its duration was actually changed,
    /// so editing a note never rounds a 25m 40s session to 26m.
    private var amountToSave: Double {
        guard goal.kind == .time else { return amount }
        if let entry, minutes == initialMinutes { return entry.amount }
        return Double(minutes * 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                GoalIcon(goal: goal, size: 40)
                VStack(alignment: .leading) {
                    Text(entry == nil ? "Log progress" : "Edit entry").font(.title3.weight(.bold))
                    Text(goal.name).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            Form {
                if goal.kind == .time {
                    Stepper(value: $minutes, in: isCorrection ? -720...(-1) : 1...720, step: entry == nil ? 5 : 1) {
                        LabeledContent(isCorrection ? "Correction" : "Duration",
                                       value: (isCorrection ? "−" : "") + Formatting.duration(Double(abs(minutes) * 60)))
                    }
                } else {
                    LabeledContent("Amount") {
                        HStack {
                            TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...2)))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                                .disabled(amountIsLocked)
                            Text(entry?.bookID != nil ? "pages" : goal.displayUnit).foregroundStyle(.secondary)
                        }
                    }
                }
                DatePicker("When", selection: $date, in: ...Date.now)
                TextField("Note", text: $note, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...3)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                if let entry {
                    Button("Delete", role: .destructive) {
                        store.deleteEntry(entry)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Log" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PillButtonStyle(tint: goal.tint))
                    .disabled(goal.kind != .time && amount == 0)
            }
            .padding(16)
        }
        .frame(width: 440, height: 400)
        .background(AmbientBackground(primary: goal.tint))
    }

    private func save() {
        let value = amountToSave
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if var edited = entry {
            if !amountIsLocked { edited.amount = value }
            edited.date = date
            edited.note = trimmed
            store.updateEntry(edited)
        } else {
            store.log(value, for: goal, at: date, note: trimmed)
        }
        dismiss()
    }
}

/// Add or edit a link: a URL, or a local file or folder picked from disk.
struct LinkEditor: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    let link: GoalLink?
    @State private var title: String
    @State private var address: String
    @State private var bookmark: Data?
    /// The file path the bookmark was made for; a retyped path needs a new one.
    @State private var bookmarkPath: String?
    @State private var opensWithFocus: Bool

    init(goalID: UUID, link: GoalLink?) {
        self.goalID = goalID
        self.link = link
        _title = State(initialValue: link?.title ?? "")
        _address = State(initialValue: link.map { $0.url.isFileURL ? $0.url.path(percentEncoded: false) : $0.url.absoluteString } ?? "")
        _bookmark = State(initialValue: link?.bookmark)
        _bookmarkPath = State(initialValue: link.flatMap { $0.url.isFileURL ? $0.url.path(percentEncoded: false) : nil })
        _opensWithFocus = State(initialValue: link?.opensWithFocus ?? false)
    }

    /// Accepts full URLs, app links like notion:// or obsidian://, bare domains, and file paths.
    private var url: URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(filePath: (trimmed as NSString).expandingTildeInPath)
        }
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty, trimmed.contains(":") {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    var body: some View {
        let goal = store.goal(goalID)
        VStack(alignment: .leading, spacing: 0) {
            Text(link == nil ? "Add link" : "Edit link")
                .font(.title3.weight(.bold))
                .padding(20)
            Form {
                TextField("Address", text: $address, prompt: Text("https://…, notion://…, or a file"))
                HStack {
                    Spacer()
                    Button("Choose File or Folder…", action: chooseFile)
                        .controlSize(.small)
                }
                TextField("Title", text: $title, prompt: Text(url.map { GoalLink(title: "", url: $0).displayTitle } ?? "Optional"))
                if goal?.kind == .time {
                    Toggle("Open when a focus session starts", isOn: $opensWithFocus)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(link == nil ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PillButtonStyle(tint: goal?.tint ?? .accentColor))
                    .disabled(url == nil)
            }
            .padding(16)
        }
        .frame(width: 460, height: 330)
        .background(AmbientBackground(primary: goal?.tint ?? .accentColor))
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Attach"
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        address = picked.path(percentEncoded: false)
        bookmark = LinkOpener.bookmark(for: picked)
        bookmarkPath = picked.path(percentEncoded: false)
        if title.isEmpty { title = picked.lastPathComponent }
    }

    private func save() {
        guard let url else { return }
        var updated = link ?? GoalLink(title: "", url: url)
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.url = url
        let matchingBookmark = bookmarkPath == url.path(percentEncoded: false) ? bookmark : nil
        updated.bookmark = url.isFileURL ? (matchingBookmark ?? LinkOpener.bookmark(for: url)) : nil
        updated.opensWithFocus = opensWithFocus
        store.perform(link == nil ? "Add Link" : "Edit Link") { $0.upsertLink(updated, in: goalID) }
        dismiss()
    }
}

/// Add or edit a book on a reading goal.
struct BookEditor: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goalID: UUID
    let book: Book?
    @State private var draft: Book
    @State private var pagesText: String
    @State private var linkText: String
    @State private var query = ""
    @State private var results: [BookSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?

    init(goalID: UUID, book: Book?) {
        self.goalID = goalID
        self.book = book
        let initial = book ?? Book(title: "")
        _draft = State(initialValue: initial)
        _pagesText = State(initialValue: initial.totalPages.map(String.init) ?? "")
        _linkText = State(initialValue: initial.link?.absoluteString ?? "")
    }

    var body: some View {
        let goal = store.goal(goalID)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                BookCover(book: draft.title.isEmpty ? Book(title: "?") : draft, tint: goal?.tint ?? .accentColor, height: 58)
                VStack(alignment: .leading) {
                    Text(book == nil ? "Add book" : "Edit book").font(.title3.weight(.bold))
                    Text(draft.title.isEmpty ? "Title, author and pages" : draft.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(20)
            Form {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a book", text: $query, prompt: Text("Search Open Library by title or author"))
                            .labelsHidden()
                        if isSearching { ProgressView().controlSize(.small) }
                    }
                    ForEach(results.prefix(5)) { result in
                        Button { apply(result) } label: { SearchResultRow(result: result) }
                            .buttonStyle(.plain)
                    }
                    if let searchError {
                        Text(searchError).font(.caption).foregroundStyle(.secondary)
                    }
                }
                TextField("Title", text: $draft.title)
                TextField("Author", text: $draft.author)
                TextField("Pages", text: $pagesText, prompt: Text("Optional, enables progress"))
                Picker("Status", selection: $draft.status) {
                    ForEach(BookStatus.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                if draft.status == .reading {
                    Stepper(value: $draft.currentPage, in: 0...max(1, Int(pagesText) ?? 10_000), step: 1) {
                        LabeledContent("Current page", value: "\(draft.currentPage)")
                    }
                }
                if draft.status == .finished {
                    LabeledContent("Rating") {
                        StarRating(rating: draft.rating ?? 0) { draft.rating = $0 == 0 ? nil : $0 }
                            .font(.title3)
                    }
                }
                TextField("Link", text: $linkText, prompt: Text("Store, Goodreads or ebook (optional)"))
                TextField("Notes", text: $draft.notes, prompt: Text("Quotes, thoughts…"), axis: .vertical)
                    .lineLimit(2...5)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(book == nil ? "Add Book" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PillButtonStyle(tint: goal?.tint ?? .accentColor))
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 480, height: 640)
        .background(AmbientBackground(primary: goal?.tint ?? .accentColor))
        .task(id: query) { await search() }
    }

    /// Searches after typing pauses, so each keystroke doesn't send a request.
    private func search() async {
        let text = query
        guard OpenLibrary.searchURL(for: text) != nil else {
            results = []
            searchError = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await OpenLibrary.search(text)
            guard !Task.isCancelled else { return }
            results = found
            searchError = found.isEmpty ? "No books found for \"\(text)\"." : nil
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            results = []
            searchError = "Couldn't reach Open Library. You can still fill the details in by hand."
        }
    }

    private func apply(_ result: BookSearchResult) {
        draft.title = result.title
        draft.author = result.author
        draft.coverURL = result.coverURL
        pagesText = result.pages.map(String.init) ?? pagesText
        linkText = result.link.absoluteString
        results = []
        query = ""
    }

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = draft.author.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalPages = Int(pagesText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        let trimmedLink = linkText.trimmingCharacters(in: .whitespaces)
        let link = trimmedLink.isEmpty ? nil : URL(string: trimmedLink.contains("://") ? trimmedLink : "https://\(trimmedLink)")
        let edited = draft
        let original = book
        let now = Date.now
        // Merge onto the book as stored now: pages logged from a widget while this sheet was open
        // must not be undone by the copy taken when it opened.
        store.perform(book == nil ? "Add Book" : "Edit Book") { data in
            var current = original.flatMap { original in data.goal(goalID)?.books.first { $0.id == original.id } } ?? edited
            current.title = title
            current.author = author
            current.totalPages = totalPages
            current.rating = edited.rating
            current.notes = edited.notes
            current.link = link
            current.coverURL = edited.coverURL
            let statusChanged = original == nil || edited.status != original?.status
            // Finishing goes through finishBook below, which also logs the pages left.
            let finishing = statusChanged && edited.status == .finished && current.status != .finished
            if statusChanged && !finishing { current.status = edited.status }
            if current.status == .reading && current.startedAt == nil { current.startedAt = now }
            if current.status != .finished { current.finishedAt = nil }
            // Only a page the user changed in this sheet moves the bookmark, logged as pages read.
            var pageDelta = 0
            if let original, edited.currentPage != original.currentPage, current.status == .reading {
                pageDelta = edited.currentPage - current.currentPage
                current.currentPage = edited.currentPage
            }
            if let totalPages { current.currentPage = min(current.currentPage, totalPages) }
            data.upsertBook(current, in: goalID)
            if pageDelta != 0 {
                data.log(Double(pageDelta), for: goalID, at: now, bookID: current.id)
            }
            if finishing {
                data.finishBook(current.id, in: goalID, rating: edited.rating, at: now)
            }
        }
        dismiss()
    }
}

/// A catalog match: cover, title, author, year and length.
private struct SearchResultRow: View {
    let result: BookSearchResult
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            BookCover(book: result.makeBook(), tint: .accentColor, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.callout.weight(.semibold)).lineLimit(1)
                Text([result.author, result.year.map(String.init), result.pages.map { "\($0) pages" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(isHovered ? Color.accentColor : Color.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
