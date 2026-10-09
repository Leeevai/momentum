import MomentumCore
import SwiftUI

/// The last seven days looked back on: focus against the week before, perfect days, each goal's
/// record, the wins written in the journal and the awards earned.
struct WeekReviewSheet: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let review = store.engine.weekReview(endingAt: store.now)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SheetHeader(symbol: "calendar.badge.checkmark", tint: .teal, title: "Your week",
                            subtitle: review.range.start.formatted(.dateTime.month(.abbreviated).day()) + " to "
                                + review.range.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    StatTile(title: "Focused", value: Formatting.duration(review.focusSeconds), systemImage: "timer", tint: .indigo,
                             caption: review.focusChange.map { change in
                                 (change >= 0 ? "Up " : "Down ") + Formatting.percent(abs(change)) + " on last week"
                             } ?? "No focus the week before")
                    StatTile(title: "Perfect days", value: "\(review.perfectDays) of 7", systemImage: "star.fill", tint: .green)
                    StatTile(title: "Active days", value: "\(review.activeDays) of 7", systemImage: "flame.fill", tint: .orange)
                    StatTile(title: "Mood", value: review.averageMood.flatMap { Mood(rawValue: Int($0.rounded())) }?.title ?? "Not rated",
                             systemImage: review.averageMood.flatMap { Mood(rawValue: Int($0.rounded())) }?.symbolName ?? "cloud.sun.fill",
                             tint: .teal)
                }
                if let best = review.bestDay {
                    Label("Best day: \(best.formatted(.dateTime.weekday(.wide)))", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
                if !review.goals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Goals", systemImage: "target").font(.headline)
                        ForEach(review.goals) { week in
                            if let goal = store.goal(week.goalID) {
                                HStack(spacing: 10) {
                                    GoalIcon(goal: goal, size: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(goal.name).font(.callout.weight(.semibold)).lineLimit(1)
                                            Spacer()
                                            Text(record(week, goal: goal))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                        }
                                        ProgressBar(progress: week.due > 0 ? Double(week.met) / Double(week.due) : 0, color: goal.color, height: 5)
                                    }
                                }
                            }
                        }
                    }
                    .glassCard(cornerRadius: 20)
                }
                if !review.wins.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wins", systemImage: "trophy.fill").font(.headline).foregroundStyle(.orange)
                        ForEach(review.wins) { win in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(win.day.date().formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, alignment: .leading)
                                Text(win.text)
                            }
                        }
                    }
                    .glassCard(tint: .orange, cornerRadius: 20)
                }
                if !review.achievements.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Awards earned", systemImage: "rosette").font(.headline)
                        ScrollView(.horizontal) {
                            HStack(spacing: 16) {
                                ForEach(review.achievements) { achievement in
                                    VStack(spacing: 6) {
                                        MedalView(achievement: achievement, size: 56)
                                        Text(achievement.title).font(.caption.weight(.semibold))
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                }
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button {
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: store.now) ?? store.now
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            store.sheet = .plan(DayID(tomorrow))
                        }
                    } label: {
                        Label("Plan tomorrow", systemImage: "sun.horizon.fill")
                    }
                    .primaryActionStyle(.teal)
                }
            }
            .padding(26)
        }
        .sheetFrame(width: 560, height: 680)
    }

    private func record(_ week: WeekReview.GoalWeek, goal: Goal) -> String {
        let logged = week.amount > 0 ? " · " + goal.formatLogged(week.amount) : ""
        if goal.effectivePeriod == .daily && goal.kind != .milestones && goal.kind != .books {
            return "\(week.met) of \(week.due) days" + logged
        }
        return (week.met > 0 ? "Target met" : "In progress") + logged
    }
}
