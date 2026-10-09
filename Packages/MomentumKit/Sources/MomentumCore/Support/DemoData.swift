import Foundation

extension AppData {
    /// A realistic, deterministic data set: widget gallery previews, screenshots, and tests.
    public static func demo(now: Date = .now, calendar: Calendar = .current) -> AppData {
        var random = SeededRandom(seed: 42)
        let created = calendar.date(byAdding: .day, value: -150, to: calendar.startOfDay(for: now)) ?? now
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
        }
        func at(_ offset: Int, hour: Int, minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day(offset)) ?? day(offset)
        }

        var deepWork = Goal(
            name: "Deep work", symbol: "laptopcomputer", color: .indigo, category: "Work",
            details: "Two protected hours a day on the thing that matters most.",
            kind: .time, period: .daily, target: 2 * 3600, streakMinimum: 30 * 60, weekdays: Set(2...6), focusMinutes: 50,
            reminder: ReminderSchedule(hour: 9, minute: 30), createdAt: created)
        deepWork.links = [
            GoalLink(title: "Momentum repo", url: URL(string: "https://github.com/Leeevai/momentum")!, opensWithFocus: true),
            GoalLink(title: "Roadmap", url: URL(string: "https://github.com/Leeevai/momentum/projects")!),
        ]

        var reading = Goal(
            name: "Reading challenge", symbol: "books.vertical.fill", color: .orange, category: "Reading",
            details: "24 books this year: fiction and non-fiction, alternating.",
            kind: .books, period: .yearly, target: 24, quickAddStep: 10, createdAt: created)
        reading.links = [GoalLink(title: "Goodreads", url: URL(string: "https://www.goodreads.com")!)]

        let exercise = Goal(
            name: "Exercise", symbol: "figure.run", color: .green, category: "Fitness",
            kind: .count, unit: "workouts", period: .weekly, target: 4, createdAt: created)

        var spanish = Goal(
            name: "Learn Spanish", symbol: "character.bubble.fill", color: .red, category: "Learning",
            kind: .time, period: .daily, target: 15 * 60, quickAddStep: 5 * 60, focusMinutes: 15, createdAt: created)
        spanish.links = [GoalLink(title: "Duolingo", url: URL(string: "https://www.duolingo.com/learn")!, opensWithFocus: true)]

        var novel = Goal(
            name: "Write a novel", symbol: "pencil.and.scribble", color: .purple, category: "Creative",
            details: "First draft before the end of the year.",
            kind: .amount, unit: "words", period: .total, target: 50_000,
            deadline: calendar.date(byAdding: .day, value: 75, to: now), quickAddStep: 500, createdAt: created)
        novel.links = [GoalLink(title: "Manuscript", url: URL(string: "https://docs.google.com/document")!)]

        var launch = Goal(
            name: "Launch portfolio", symbol: "paperplane.fill", color: .pink, category: "Work",
            kind: .milestones, target: 0, createdAt: created)
        let steps = ["Pick a domain", "Design the home page", "Write three case studies", "Set up analytics", "Ask 5 friends for feedback", "Publish"]
        launch.milestones = steps.enumerated().map { index, title in
            Milestone(title: title, completedAt: index < 3 ? day(-40 + index * 12) : nil)
        }

        let meditate = Goal(
            name: "Meditate", symbol: "figure.mind.and.body", color: .teal, category: "Mindfulness",
            kind: .time, period: .daily, target: 10 * 60, quickAddStep: 5 * 60, focusMinutes: 10, createdAt: created)

        var data = AppData(goals: [deepWork, reading, exercise, spanish, novel, launch, meditate])

        // Books: a few finished this year, one in progress, a short queue.
        let library: [(String, String, Int)] = [
            ("Deep Work", "Cal Newport", 296), ("Atomic Habits", "James Clear", 320), ("Project Hail Mary", "Andy Weir", 476),
            ("The Pragmatic Programmer", "Hunt & Thomas", 352), ("Piranesi", "Susanna Clarke", 272), ("Four Thousand Weeks", "Oliver Burkeman", 288),
            ("Dune", "Frank Herbert", 412), ("Thinking in Systems", "Donella Meadows", 240),
        ]
        var books: [Book] = []
        var readingDay = -140
        for (index, item) in library.enumerated() {
            var book = Book(title: item.0, author: item.1, totalPages: item.2, addedAt: created)
            if index < 6 {
                book.status = .finished
                book.startedAt = day(readingDay)
                readingDay += 18 + random.next(upTo: 6)
                book.finishedAt = at(readingDay, hour: 22)
                book.currentPage = item.2
                book.rating = 3 + random.next(upTo: 3)
            } else if index == 6 {
                book.status = .reading
                book.startedAt = day(-9)
                book.currentPage = 168
            }
            books.append(book)
        }
        data.goals[1].books = books

        for offset in stride(from: -149, through: 0, by: 1) {
            let date = day(offset)
            let weekday = calendar.component(.weekday, from: date)
            let isToday = offset == 0

            // Deep work: most weekdays, in 50-minute blocks, sometimes short.
            if deepWork.weekdays.contains(weekday) && random.chance(0.88) {
                let blocks = isToday ? 1 : (random.chance(0.8) ? 3 : 2)
                for block in 0..<blocks {
                    let minutes = isToday ? 55 : 42 + random.next(upTo: 14)
                    data.entries.append(LogEntry(goalID: deepWork.id, date: at(offset, hour: 9 + block * 2, minute: random.next(upTo: 30)), amount: Double(minutes * 60), source: .timer,
                                                 note: block == 0 && random.chance(0.3) ? ["Refactored the progress engine", "Wrote widget timelines", "Fixed the streak edge case", "Planned the next release"][random.next(upTo: 4)] : ""))
                }
            }
            // Reading: pages most evenings.
            if random.chance(0.8) {
                let pages = isToday ? 24 : 12 + random.next(upTo: 30)
                data.entries.append(LogEntry(goalID: reading.id, date: at(offset, hour: 21, minute: 30), amount: Double(pages), source: .manual))
            }
            // Exercise: about four times a week.
            if !isToday && random.chance(0.6) {
                data.entries.append(LogEntry(goalID: exercise.id, date: at(offset, hour: 7), amount: 1))
            }
            // Spanish: a long streak in the last weeks.
            if offset > -60 || random.chance(0.7) {
                let minutes = isToday ? 9 : 15 + random.next(upTo: 10)
                data.entries.append(LogEntry(goalID: spanish.id, date: at(offset, hour: 13), amount: Double(minutes * 60), source: .timer))
            }
            // Novel: bursts of writing.
            if offset > -90 && random.chance(0.55) {
                data.entries.append(LogEntry(goalID: novel.id, date: at(offset, hour: 20), amount: Double(400 + random.next(upTo: 900))))
            }
            // Meditation: mornings.
            if random.chance(0.75) && !isToday {
                data.entries.append(LogEntry(goalID: meditate.id, date: at(offset, hour: 7, minute: 30), amount: Double((10 + random.next(upTo: 6)) * 60), source: .timer))
            }
        }
        data.entries.sort { $0.date < $1.date }

        // Habit stack: Spanish right after meditating, on day 19 of a 30-day challenge.
        data.goals[3].stackAfter = meditate.id
        data.goals[3].challenge = Challenge(start: DayID(day(-18), calendar: calendar), days: 30)

        // Journal: most evenings rated, with better moods on better days; plans on most mornings.
        let engine = ProgressEngine(data: data, calendar: calendar)
        let wins = ["Finished the chapter", "Shipped the widget fix", "Ran 5 km without stopping", "A whole Spanish podcast, understood",
                    "Inbox zero before lunch", "Wrote 1,200 words", "Deep work before the meetings"]
        let intentions = ["Protect the morning for deep work", "Small steps, every goal", "Finish what I started", "Be present, one thing at a time"]
        for offset in stride(from: -45, through: -1, by: 1) where random.chance(0.8) {
            let date = day(offset)
            let summary = engine.daySummary(date, now: now)
            let base = 2 + Int(((summary.completion ?? 0.5) * 3).rounded())
            let mood = Mood(rawValue: min(5, max(1, base + random.next(upTo: 2) - (random.chance(0.3) ? 1 : 0))))
            data.updateJournal(for: DayID(date, calendar: calendar), at: at(offset, hour: 21, minute: 40)) { entry in
                entry.mood = mood
                entry.energy = Energy(rawValue: min(5, max(1, base - 1 + random.next(upTo: 3))))
                if random.chance(0.6) { entry.win = wins[random.next(upTo: wins.count)] }
                if random.chance(0.5) {
                    entry.intention = intentions[random.next(upTo: intentions.count)]
                    entry.priorities = [deepWork.id, spanish.id, reading.id].prefix(1 + random.next(upTo: 3)).map { $0 }
                }
            }
        }
        data.updateJournal(for: DayID(now, calendar: calendar), at: at(0, hour: 8, minute: 5)) { entry in
            entry.intention = "Ship the Pomodoro release, then read in the sun"
            entry.priorities = [deepWork.id, spanish.id, reading.id]
        }

        // Achievements earned along the way, dated over the past months.
        let earned = data.recordAchievements(now: now, calendar: calendar)
        for (index, achievement) in earned.enumerated() {
            data.achievements[achievement.id] = at(-(index * 9 % 140) - 1, hour: 18 + index % 4)
        }
        return data
    }
}

/// A tiny deterministic generator (SplitMix64), so demo data is identical on every run.
/// SplitMix64: a small, fast, deterministic generator.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 { nextValue() }

    mutating func nextValue() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(upTo bound: Int) -> Int {
        Int(nextValue() % UInt64(max(1, bound)))
    }

    mutating func chance(_ probability: Double) -> Bool {
        Double(nextValue() % 10_000) / 10_000 < probability
    }
}
