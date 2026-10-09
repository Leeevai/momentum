import MomentumCore
import SwiftUI

/// The controls beside a goal's hero ring, specific to what the goal measures.
struct TrackingControls: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        switch goal.kind {
        case .time: TimeControls(goal: goal)
        case .count, .amount: AmountControls(goal: goal)
        case .milestones: MilestoneControls(goal: goal)
        case .books: BookControls(goal: goal)
        }
    }
}

private struct TimeControls: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let session = store.data.session, session.goalID == goal.id {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.plannedDuration == nil ? "Elapsed" : "Time left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    SessionClockText(session: session)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(goal.color.linear)
                }
                HStack(spacing: 10) {
                    Button {
                        store.togglePause()
                    } label: {
                        Label(session.isRunning ? "Pause" : "Resume", systemImage: session.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: goal.tint, prominent: false))
                    Button {
                        store.stopFocus()
                    } label: {
                        Label("Stop & save", systemImage: "stop.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: goal.tint))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready when you are")
                        .font(.title3.weight(.semibold))
                    Text(goal.focusMinutes.map { "Sessions default to \($0) minutes." } ?? "Sessions run until you stop them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button {
                        store.toggleFocus(goal)
                    } label: {
                        Label(goal.focusMinutes.map { "Focus \($0)m" } ?? "Start focus", systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle(tint: goal.tint))
                    .keyboardShortcut(.return, modifiers: .command)
                    Menu {
                        FocusLengthMenu(goal: goal)
                    } label: {
                        Label("Length", systemImage: "timer")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    if goal.links.contains(where: \.opensWithFocus) {
                        Label("Opens \(goal.links.filter(\.opensWithFocus).count) link\(goal.links.filter(\.opensWithFocus).count == 1 ? "" : "s")", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            StreakSafeNote(goal: goal)
            ManualLogRow(goal: goal)
        }
    }
}

/// Explains the minimum when a goal has one: whether today's amount already protects the streak.
private struct StreakSafeNote: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        if let minimum = goal.streakMinimum, !store.engine.isComplete(goal, now: store.now) {
            let safe = store.engine.keepsStreak(goal, periodContaining: store.now, now: store.now)
            Label(safe ? "Streak safe: you've done the minimum today" : "\(goal.format(minimum)) keeps your streak today",
                  systemImage: safe ? "shield.checkered" : "shield")
                .font(.callout)
                .foregroundStyle(safe ? Color.orange : Color.secondary)
        }
    }
}

private struct AmountControls: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        let engine = store.engine
        let remaining = max(0, engine.target(for: goal) - engine.currentAmount(for: goal, now: store.now))
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(remaining > 0 ? "\(goal.format(remaining)) to go" : "Target reached 🎉")
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
                Text(goal.targetDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            StreakSafeNote(goal: goal)
            HStack(spacing: 10) {
                GoalPrimaryButton(goal: goal)
                    .keyboardShortcut(.return, modifiers: .command)
                Button {
                    store.sheet = .log(goalID: goal.id)
                } label: {
                    Label("Log…", systemImage: "square.and.pencil")
                }
                .buttonStyle(PillButtonStyle(tint: goal.tint, prominent: false))
                Button {
                    store.perform("Undo Log") { $0.log(-goal.quickAddStep, for: goal.id, note: "Correction") }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(CircleButtonStyle(tint: goal.tint, size: 32, prominent: false))
                .help("Subtract \(goal.format(goal.quickAddStep)) from today")
                .disabled(engine.amount(for: goal, on: store.now, now: store.now) <= 0)
            }
        }
    }
}

/// "Log time" and quick corrections for time goals.
private struct ManualLogRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.sheet = .log(goalID: goal.id)
            } label: {
                Label("Log time…", systemImage: "square.and.pencil")
            }
            Button("+\(Formatting.duration(goal.quickAddStep))") {
                store.perform("Log Progress") { $0.log(goal.quickAddStep, for: goal.id) }
            }
            Button("−\(Formatting.duration(goal.quickAddStep))") {
                store.perform("Undo Log") { $0.log(-goal.quickAddStep, for: goal.id, note: "Correction") }
            }
            .disabled(store.engine.amount(for: goal, on: store.now, now: store.now) <= 0)
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct MilestoneControls: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal

    var body: some View {
        let done = goal.milestones.filter(\.isDone).count
        VStack(alignment: .leading, spacing: 12) {
            Text(goal.milestones.isEmpty ? "Break it into milestones" : "\(done) of \(goal.milestones.count) milestones")
                .font(.title3.weight(.semibold))
            if let next = goal.milestones.first(where: { !$0.isDone }) {
                HStack(spacing: 10) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(goal.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next up").font(.caption).foregroundStyle(.secondary)
                        Text(next.title).font(.body.weight(.medium))
                    }
                }
                GoalPrimaryButton(goal: goal)
            } else if !goal.milestones.isEmpty {
                Label("Every milestone is done. Time to celebrate, or archive the goal.", systemImage: "party.popper")
                    .foregroundStyle(.secondary)
            } else {
                Text("Add the steps below; each one you check off moves the ring.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BookControls: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    @State private var pageText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let book = goal.currentBook {
                HStack(alignment: .top, spacing: 12) {
                    BookCover(book: book, tint: goal.tint, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Currently reading").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        Text(book.title).font(.title3.weight(.semibold)).lineLimit(1)
                        if !book.author.isEmpty { Text(book.author).font(.callout).foregroundStyle(.secondary) }
                    }
                }
                if let fraction = book.fraction {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressBar(progress: fraction, color: goal.color, height: 7)
                        Text("Page \(book.currentPage) of \(book.totalPages ?? 0) · \(book.pagesLeft ?? 0) left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 360)
                }
                HStack(spacing: 10) {
                    GoalPrimaryButton(goal: goal)
                    TextField("Page", text: $pageText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onSubmit { setPage(book) }
                    Button("Set page") { setPage(book) }
                        .disabled(Int(pageText) == nil)
                    Button {
                        store.perform("Finish Book") { $0.finishBook(book.id, in: goal.id) }
                    } label: {
                        Label("Finished", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(PillButtonStyle(tint: goal.tint, prominent: false, compact: true))
                }
            } else {
                Text(goal.books.contains { $0.status == .wantToRead } ? "Pick your next book" : "Start your reading list")
                    .font(.title3.weight(.semibold))
                Text("Add books you want to read, then log pages as you go. Finishing a book moves the ring.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    store.sheet = .book(goalID: goal.id, book: nil)
                } label: {
                    Label("Add a book", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle(tint: goal.tint))
            }
        }
    }

    private func setPage(_ book: Book) {
        guard let page = Int(pageText) else { return }
        store.perform("Log Pages") { $0.setPage(page, in: book.id, of: goal.id) }
        pageText = ""
    }
}
