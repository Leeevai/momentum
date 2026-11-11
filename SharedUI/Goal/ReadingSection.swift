import MomentumCore
import SwiftUI

extension Goal {
    /// Whether the goal screen shows the card for what the goal follows (`Goal.follows`): a books
    /// goal has its reading list instead, and a time goal shows it once a video has been added.
    var showsFollowingCard: Bool {
        switch follows {
        case .book: kind != .books
        case .course, .series: true
        case .video: !books.isEmpty
        case nil: false
        }
    }

    /// What follows the goal's item along, for the card and its alert: "Set Page", "Set Lesson",
    /// "Watched Up To".
    var setPositionTitle: String {
        guard let part = followedParts?.one else { return "Watched Up To" }
        return "Set \(part.capitalized)"
    }
}

extension BookStatus {
    /// The status in words for what it's on: a book's own, or for a course, a series or a video,
    /// words that aren't about reading.
    func title(for kind: FollowKind) -> String {
        guard kind != .book else { return title }
        switch self {
        case .wantToRead: return "Up next"
        case .reading: return "In progress"
        case .finished: return "Finished"
        case .abandoned: return "Set aside"
        }
    }
}

/// What a goal follows (`Goal.follows`): the book being read on a goal counted in pages, the
/// course, the series, or the video on a time goal. It shows the position reached, what's left,
/// and a way to jump to a position. Amounts logged on the goal move it (`AppData.logReading`).
struct ReadingSection: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    @State private var settingPage: Book?
    @State private var pageText = ""

    private var kind: FollowKind { goal.follows ?? .book }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(kind.sectionTitle, systemImage: kind.symbolName, trailing: goal.currentBook == nil ? AnyView(addButton) : nil)
            if let book = goal.currentBook {
                CurrentBookRow(goal: goal, book: book) {
                    pageText = kind == .video ? Formatting.clock(Double(book.currentPage)) : "\(book.currentPage)"
                    settingPage = book
                }
            } else {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Books set aside (or added for later) stay here to pick up again, at their page.
                ForEach(goal.books.filter { $0.status == .abandoned || $0.status == .wantToRead }) { book in
                    WaitingBookRow(goal: goal, book: book)
                }
                let finished = goal.books.filter { $0.status == .finished }.count
                if finished > 0 {
                    Label("\(finished) \(finished == 1 ? kind.noun : kind.pluralNoun) finished", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .glassCard(tint: goal.tint)
        .alert(goal.setPositionTitle, isPresented: isSettingPage, presenting: settingPage) { book in
            TextField(kind == .video ? "1:23:40" : goal.setPositionTitle, text: $pageText)
                #if os(iOS)
                .keyboardType(kind == .video ? .numbersAndPunctuation : .numberPad)
                #endif
            Button("Set") { setPage(of: book) }
            Button("Cancel", role: .cancel) {}
        } message: { book in
            Text(setMessage(book))
        }
    }

    private var emptyText: String {
        switch kind {
        case .book:
            "Add the book you're reading, and the pages you log here move its bookmark: you'll always know the page you reached and how many are left."
        case .course:
            "Add the course you're taking, and the lessons you log here move it along: you'll always know where you are and how many are left."
        case .series:
            "Add the series you're watching, and the episodes you log here move it along: you'll always know where you are and how many are left."
        case .video:
            "Add the video you're watching and its length, and log the time you watched up to: the time in between counts."
        }
    }

    /// What the position alert asks for, and what setting it logs.
    private func setMessage(_ book: Book) -> String {
        let total = book.totalPages.flatMap { $0 > 0 ? $0 : nil }
        switch kind {
        case .book:
            return total.map { "The page you've reached, of \($0). The pages in between are logged as read." }
                ?? "The page you've reached. The pages in between are logged as read."
        case .course, .series:
            let parts = goal.followedParts ?? (one: "lesson", many: "lessons")
            let verb = kind == .course ? "done" : "watched"
            let of = total.map { ", of \($0)" } ?? ""
            return "The last \(parts.one) you finished\(of). The \(parts.many) in between are logged as \(verb)."
        case .video:
            let of = total.map { ", of \(Formatting.clock(Double($0)))" } ?? ""
            return "The time you watched up to, like 1:23:40\(of). The time in between is logged as watched."
        }
    }

    private var addButton: some View {
        Button {
            store.sheet = .book(goalID: goal.id, book: nil)
        } label: {
            Label("Add \(kind.title)", systemImage: "plus")
        }
        .secondaryActionStyle(goal.tint, compact: true)
    }

    private var isSettingPage: Binding<Bool> {
        Binding(get: { settingPage != nil }, set: { if !$0 { settingPage = nil } })
    }

    private func setPage(of book: Book) {
        let text = pageText.trimmingCharacters(in: .whitespaces)
        let typed = kind == .video ? Formatting.seconds(fromClock: text) : Int(text)
        guard let page = typed, page >= 0 else { return }
        store.perform(goal.setPositionTitle) { $0.setPage(page, in: book.id, of: goal.id) }
    }
}

/// A book set aside or waiting, with the page it stopped at and Resume.
private struct WaitingBookRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            BookCover(book: book, tint: goal.tint, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(book.currentPage > 0 ? "Stopped at \(stoppedAt)" : book.status.title(for: goal.follows ?? .book))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Button("Resume") {
                store.perform("Start Book") { $0.startReading(book.id, in: goal.id) }
            }
            .secondaryActionStyle(goal.tint, compact: true)
        }
    }

    /// "page 12 of 300", "lesson 7 of 24", "1:23:40 of 2:10:00".
    private var stoppedAt: String {
        let text = goal.positionText(of: book)
        return text.prefix(1).lowercased() + text.dropFirst()
    }
}

private struct CurrentBookRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let book: Book
    let setPage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                BookCover(book: book, tint: goal.tint, height: 72)
                details
                Spacer(minLength: 0)
                menu
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.title)
                .font(.headline)
                .lineLimit(2)
            if !book.author.isEmpty {
                Text(book.author)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(pageLine)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .padding(.top, 2)
            if let fraction = book.fraction {
                ProgressBar(progress: fraction, color: goal.color, height: 6)
                    .frame(maxWidth: 220)
            }
        }
    }

    /// "Page 134 of 420 · 286 pages left", "Lesson 7 of 24 · 17 lessons left", or "Page 134"
    /// without a length.
    private var pageLine: String {
        [goal.positionText(of: book), goal.remainingText(of: book)].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: setPage) {
            Label("\(goal.setPositionTitle)…", systemImage: "bookmark")
        }
        .secondaryActionStyle(goal.tint, compact: true)
        Button {
            store.perform("Finish Book") { $0.finishBook(book.id, in: goal.id) }
        } label: {
            Label("Finished", systemImage: "checkmark")
        }
        .secondaryActionStyle(goal.tint, compact: true)
        .help("Mark it finished; what's left of it is logged")
    }

    /// Edit, or set the book aside. No Remove: it would take the pages logged in it with it.
    private var menu: some View {
        Menu {
            Button("Edit…") { store.sheet = .book(goalID: goal.id, book: book) }
            Button("Set Aside") { store.perform("Set Book Aside") { $0.abandonBook(book.id, in: goal.id) } }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Book actions")
    }
}
