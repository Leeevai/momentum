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
    @State private var date: Date
    @State private var note: String

    init(goal: Goal, entry: LogEntry? = nil) {
        self.goal = goal
        self.entry = entry
        let value = entry?.amount ?? goal.quickAddStep
        _amount = State(initialValue: value)
        _minutes = State(initialValue: max(1, Int((value / 60).rounded())))
        _date = State(initialValue: entry?.date ?? .now)
        _note = State(initialValue: entry?.note ?? "")
    }

    /// Page logs move a book's bookmark, so their amount is fixed once logged.
    private var amountIsLocked: Bool { entry?.bookID != nil }

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
                    Stepper(value: $minutes, in: 1...720, step: entry == nil ? 5 : 1) {
                        LabeledContent("Duration", value: Formatting.duration(Double(minutes * 60)))
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
        let value = goal.kind == .time ? Double(minutes * 60) : amount
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
    @State private var opensWithFocus: Bool

    init(goalID: UUID, link: GoalLink?) {
        self.goalID = goalID
        self.link = link
        _title = State(initialValue: link?.title ?? "")
        _address = State(initialValue: link.map { $0.url.isFileURL ? $0.url.path(percentEncoded: false) : $0.url.absoluteString } ?? "")
        _bookmark = State(initialValue: link?.bookmark)
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
                    .onChange(of: address) { _, _ in if !(url?.isFileURL ?? false) { bookmark = nil } }
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
        if title.isEmpty { title = picked.lastPathComponent }
    }

    private func save() {
        guard let url else { return }
        var updated = link ?? GoalLink(title: "", url: url)
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.url = url
        updated.bookmark = url.isFileURL ? (bookmark ?? LinkOpener.bookmark(for: url)) : nil
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
                TextField("Title", text: $draft.title)
                TextField("Author", text: $draft.author)
                TextField("Pages", text: $pagesText, prompt: Text("Optional, enables progress"))
                Picker("Status", selection: $draft.status) {
                    ForEach(BookStatus.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                if draft.status == .reading {
                    Stepper(value: $draft.currentPage, in: 0...(Int(pagesText) ?? 10_000), step: 1) {
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
        .frame(width: 480, height: 600)
        .background(AmbientBackground(primary: goal?.tint ?? .accentColor))
    }

    private func save() {
        var updated = draft
        updated.title = updated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.author = updated.author.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.totalPages = Int(pagesText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        let trimmedLink = linkText.trimmingCharacters(in: .whitespaces)
        updated.link = trimmedLink.isEmpty ? nil : URL(string: trimmedLink.contains("://") ? trimmedLink : "https://\(trimmedLink)")
        let previousStatus = book?.status
        let now = Date.now
        if updated.status == .reading && updated.startedAt == nil { updated.startedAt = now }
        if updated.status == .finished && previousStatus != .finished {
            updated.finishedAt = updated.finishedAt ?? now
            if let total = updated.totalPages { updated.currentPage = total }
        }
        if updated.status != .finished { updated.finishedAt = nil }
        let pageDelta = updated.currentPage - (book?.currentPage ?? 0)
        let bookID = updated.id
        store.perform(book == nil ? "Add Book" : "Edit Book") { data in
            data.upsertBook(updated, in: goalID)
            if book != nil, pageDelta != 0 {
                data.log(Double(pageDelta), for: goalID, at: now, bookID: bookID)
            }
        }
        dismiss()
    }
}
