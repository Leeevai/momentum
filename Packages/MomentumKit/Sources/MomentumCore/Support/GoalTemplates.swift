import Foundation

/// A ready-made starting point in the New Goal gallery.
public struct GoalTemplate: Identifiable, Sendable {
    public var id: String
    public var subtitle: String
    public var prototype: Goal

    /// A fresh goal from the template: new id, created now.
    public func makeGoal(at now: Date = .now) -> Goal {
        var goal = prototype
        goal.id = UUID()
        goal.createdAt = now
        goal.milestones = prototype.milestones.map { Milestone(title: $0.title) }
        return goal
    }

    public static let all: [GoalTemplate] = [
        GoalTemplate(id: "deep-work", subtitle: "2h of focused work on weekdays", prototype: Goal(
            name: "Deep work", icon: "💻", color: .indigo, category: "Work", kind: .time, period: .daily,
            target: 2 * 3600, weekdays: Set(2...6), focusMinutes: 50)),
        GoalTemplate(id: "reading-challenge", subtitle: "Finish 24 books this year", prototype: Goal(
            name: "Reading challenge", icon: "📚", color: .orange, category: "Reading", kind: .books, period: .yearly,
            target: 24, quickAddStep: 10)),
        GoalTemplate(id: "read-daily", subtitle: "20 pages every day", prototype: Goal(
            name: "Read every day", icon: "📖", color: .brown, category: "Reading", kind: .amount, unit: "pages",
            period: .daily, target: 20, quickAddStep: 10)),
        GoalTemplate(id: "exercise", subtitle: "4 workouts a week", prototype: Goal(
            name: "Exercise", icon: "🏃", color: .green, category: "Fitness", kind: .count, unit: "workouts",
            period: .weekly, target: 4)),
        GoalTemplate(id: "meditate", subtitle: "10 mindful minutes a day", prototype: Goal(
            name: "Meditate", icon: "🧘", color: .teal, category: "Mindfulness", kind: .time, period: .daily,
            target: 10 * 60, quickAddStep: 5 * 60, focusMinutes: 10)),
        GoalTemplate(id: "language", subtitle: "15 minutes of practice daily", prototype: Goal(
            name: "Learn Spanish", icon: "🇪🇸", color: .red, category: "Learning", kind: .time, period: .daily,
            target: 15 * 60, quickAddStep: 5 * 60, focusMinutes: 15)),
        GoalTemplate(id: "write-book", subtitle: "50,000 words, one session at a time", prototype: Goal(
            name: "Write a novel", icon: "✍️", color: .purple, category: "Creative", kind: .amount, unit: "words",
            period: .total, target: 50_000, quickAddStep: 500)),
        GoalTemplate(id: "water", subtitle: "8 glasses a day", prototype: Goal(
            name: "Drink water", icon: "💧", color: .cyan, category: "Health", kind: .count, unit: "glasses",
            period: .daily, target: 8)),
        GoalTemplate(id: "run", subtitle: "Run 100 km a month", prototype: Goal(
            name: "Running", icon: "👟", color: .mint, category: "Fitness", kind: .amount, unit: "km",
            period: .monthly, target: 100, quickAddStep: 5)),
        GoalTemplate(id: "save", subtitle: "Put money aside every month", prototype: Goal(
            name: "Save money", icon: "💰", color: .yellow, category: "Finance", kind: .amount, unit: "$",
            period: .monthly, target: 500, quickAddStep: 50)),
        GoalTemplate(id: "ship-project", subtitle: "A project as a checklist of milestones", prototype: Goal(
            name: "Ship a side project", icon: "🚀", color: .pink, category: "Work", kind: .milestones, target: 0,
            milestones: ["Write the spec", "Build the prototype", "Get feedback from 5 people", "Polish and launch"].map { Milestone(title: $0) })),
        GoalTemplate(id: "learn-course", subtitle: "3 hours of study a week", prototype: Goal(
            name: "Online course", icon: "🎓", color: .blue, category: "Learning", kind: .time, period: .weekly,
            target: 3 * 3600, focusMinutes: 45)),
    ]
}
