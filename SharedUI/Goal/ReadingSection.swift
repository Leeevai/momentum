import MomentumCore
import SwiftUI

/// The book being read, on a goal counted in pages: the page reached, what's left, and a way to
/// jump to a page. Pages logged on the goal move its bookmark (`AppData.logReading`).
struct ReadingSection: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    @State private var settingPage: Book?
    @State private var pageText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Reading", systemImage: "book", trailing: goal.currentBook == nil ? AnyView(addButton) : nil)
            if let book = goal.currentBook {
                CurrentBookRow(goal: goal, book: book) {
                    pageText = "\(book.currentPage)"
                    settingPage = book
                }
            } else {
                Text("Add the book you're reading, and the pages you log here move its bookmark: you'll always know the page you reached and how many are left.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard(tint: goal.tint)
        .alert("Set Page", isPresented: isSettingPage, presenting: settingPage) { book in
            TextField("Page", text: $pageText)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Set") { setPage(of: book) }
            Button("Cancel", role: .cancel) {}
        } message: { book in
            Text(book.totalPages.map { "The page you've reached, of \($0). The pages in between are logged as read." }
                 ?? "The page you've reached. The pages in between are logged as read.")
        }
    }

    private var addButton: some View {
        Button {
            store.sheet = .book(goalID: goal.id, book: nil)
        } label: {
            Label("Add Book", systemImage: "plus")
        }
        .secondaryActionStyle(goal.tint, compact: true)
    }

    private var isSettingPage: Binding<Bool> {
        Binding(get: { settingPage != nil }, set: { if !$0 { settingPage = nil } })
    }

    private func setPage(of book: Book) {
        guard let page = Int(pageText.trimmingCharacters(in: .whitespaces)), page >= 0 else { return }
        store.perform("Set Page") { $0.setPage(page, in: book.id, of: goal.id) }
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

    /// "Page 134 of 420 · 286 left", or "Page 134" without a page count.
    private var pageLine: String {
        guard let total = book.totalPages, total > 0 else { return "Page \(book.currentPage)" }
        return "Page \(book.currentPage) of \(total) · \(max(0, total - book.currentPage)) left"
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: setPage) {
            Label("Set Page…", systemImage: "bookmark")
        }
        .secondaryActionStyle(goal.tint, compact: true)
        Button {
            store.perform("Finish Book") { $0.finishBook(book.id, in: goal.id) }
        } label: {
            Label("Finished", systemImage: "checkmark")
        }
        .secondaryActionStyle(goal.tint, compact: true)
        .help("Mark it finished; the pages left are logged as read")
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
