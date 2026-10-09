import MomentumCore
import SwiftUI

/// A month of days at a glance, each with how it went, and the selected day's plan, reflection,
/// goals and focus.
struct JournalView: View {
    @Environment(GoalStore.self) private var store
    @State private var month = Date()
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var movingForward = true
    @Namespace private var selection

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                calendarColumn
                    .frame(width: 430)
                dayColumn
                    .frame(minWidth: 380, maxWidth: .infinity, alignment: .top)
            }
            .padding(Metrics.screenPadding)
            .frame(minWidth: 860)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    calendarColumn
                    dayColumn
                }
                .padding(Metrics.screenPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LivingBackdrop(primary: .orange, secondary: .indigo))
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem {
                Button {
                    store.sheet = .review
                } label: {
                    Label("Week in Review", systemImage: "calendar.badge.checkmark")
                }
                .help("Look back on the last seven days")
            }
            ToolbarItem {
                Button("Today") { select(Calendar.current.startOfDay(for: .now)) }
                    .help("Go to today")
            }
        }
    }

    // MARK: - Calendar

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            MonthCalendar(month: $month, selected: selected, marker: selection) { day in select(day) }
            MonthStats(month: month)
            YearInPixels { day in select(day) }
        }
    }

    private var dayColumn: some View {
        ScrollView {
            DayDetail(day: selected)
                .id(selected)
                .transition(.asymmetric(insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .opacity))
        }
        .scrollContentBackground(.hidden)
        .scrollClipDisabled()
    }

    private func select(_ day: Date) {
        movingForward = day >= selected
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            selected = day
            if !Calendar.current.isDate(day, equalTo: month, toGranularity: .month) { month = day }
        }
    }
}

// MARK: - Month

private struct MonthCalendar: View {
    @Environment(GoalStore.self) private var store
    @Binding var month: Date
    let selected: Date
    let marker: Namespace.ID
    var onSelect: (Date) -> Void

    var body: some View {
        let engine = store.engine
        let calendar = Calendar.current
        let grid = engine.monthGrid(containing: month)
        let symbols = Self.weekdaySymbols(calendar)
        VStack(spacing: 14) {
            HStack {
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Spacer()
                GlassGroup(spacing: 6) {
                    HStack(spacing: 6) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                            .secondaryActionStyle(.secondary, compact: true)
                            .help("Previous month")
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                            .secondaryActionStyle(.secondary, compact: true)
                            .help("Next month")
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(symbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 6) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 6) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day {
                                DayCell(summary: engine.daySummary(day, now: store.now), isSelected: calendar.isDate(day, inSameDayAs: selected),
                                        isToday: calendar.isDateInToday(day), isFuture: day > store.now, marker: marker)
                                    .onTapGesture { onSelect(day) }
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: 52)
                            }
                        }
                    }
                }
            }
        }
        .glassCard(cornerRadius: 24, padding: 20)
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if abs(value.translation.width) > abs(value.translation.height) { shift(value.translation.width < 0 ? 1 : -1) }
        })
    }

    private func shift(_ months: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
        }
    }

    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

private struct DayCell: View {
    let summary: DaySummary
    let isSelected: Bool
    let isToday: Bool
    let isFuture: Bool
    let marker: Namespace.ID
    @State private var isHovered = false

    var body: some View {
        let completion = summary.completion ?? 0
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(isFuture ? 0.04 : 0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: completion)
                    .stroke(summary.isPerfect ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Color.accentColor.gradient),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if summary.isPerfect {
                    Circle().fill(.green.opacity(0.18))
                }
                Text(summary.day, format: .dateTime.day())
                    .font(.system(.callout, design: .rounded, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isFuture ? AnyShapeStyle(.tertiary) : (isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary)))
            }
            .frame(width: 32, height: 32)
            Group {
                if let mood = summary.journal?.mood {
                    Image(systemName: mood.symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(mood.tint)
                } else if summary.journal?.isEmpty == false {
                    Image(systemName: "text.quote")
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear
                }
            }
            .font(.system(size: 10))
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5))
                    .matchedGeometryEffect(id: "selection", in: marker)
            } else if isHovered {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.05))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovered = $0 }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var help: String {
        var parts = [summary.day.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if !summary.due.isEmpty { parts.append("\(summary.met.count) of \(summary.due.count) done") }
        if let mood = summary.journal?.mood { parts.append("mood \(mood.title.lowercased())") }
        return parts.joined(separator: ", ")
    }
}

/// The month in numbers: perfect days, days journaled, average mood and focus.
private struct MonthStats: View {
    @Environment(GoalStore.self) private var store
    let month: Date

    var body: some View {
        let engine = store.engine
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 86_400 * 30)
        let days = engine.monthGrid(containing: month).flatMap { $0 }.compactMap { $0 }.filter { $0 <= store.now }
        let summaries = days.map { engine.daySummary($0, now: store.now) }
        let mood = engine.moodReport(in: interval, now: store.now)
        let focus = summaries.reduce(0) { $0 + $1.focusSeconds }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(title: "Perfect days", value: "\(summaries.filter(\.isPerfect).count)", systemImage: "star.fill", tint: .green)
            StatTile(title: "Journaled", value: "\(summaries.filter { $0.journal?.isEmpty == false }.count) days", systemImage: "book.closed.fill", tint: .orange)
            StatTile(title: "Average mood", value: mood.averageMood.map { Mood(rawValue: Int($0.rounded()))?.title ?? "–" } ?? "–",
                     systemImage: mood.averageMood.flatMap { Mood(rawValue: Int($0.rounded())) }?.symbolName ?? "cloud.sun.fill", tint: .teal,
                     caption: mood.days > 0 ? "\(mood.days) days rated" : "Rate days to see it")
            StatTile(title: "Focused", value: Formatting.duration(focus), systemImage: "timer", tint: .indigo)
        }
    }
}

// MARK: - Day

private struct DayDetail: View {
    @Environment(GoalStore.self) private var store
    let day: Date

    var body: some View {
        let engine = store.engine
        let id = DayID(day)
        let summary = engine.daySummary(day, now: store.now)
        let entry = summary.journal
        let isFuture = day > store.now
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day, format: .dateTime.weekday(.wide))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(day, format: .dateTime.month(.wide).day().year())
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }

            journalCard(title: "Plan", symbol: "sun.horizon.fill", tint: .orange, isEmpty: entry?.hasPlan != true,
                        empty: isFuture ? "Plan ahead: set an intention and pick priorities." : "No plan written.",
                        action: entry?.hasPlan == true ? "Edit" : "Plan", route: .plan(id)) {
                if let entry {
                    if !entry.intention.isEmpty {
                        Text(entry.intention)
                            .font(.system(.title3, design: .serif).italic())
                    }
                    if !entry.priorities.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(entry.priorities.compactMap(store.goal)) { goal in
                                let met = engine.isMet(goal, periodContaining: day, now: store.now)
                                Label(goal.name, systemImage: met ? "checkmark.circle.fill" : "circle")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(met ? AnyShapeStyle(goal.tint) : AnyShapeStyle(.secondary))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(goal.tint.opacity(0.12)))
                            }
                        }
                    }
                }
            }

            if !isFuture {
                journalCard(title: "Reflection", symbol: "moon.stars.fill", tint: .indigo, isEmpty: entry?.hasReflection != true,
                            empty: "How did the day go? Rate it and note a win.",
                            action: entry?.hasReflection == true ? "Edit" : "Reflect", route: .reflect(id)) {
                    if let entry {
                        HStack(spacing: 16) {
                            if let mood = entry.mood {
                                Label(mood.title, systemImage: mood.symbolName)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(mood.tint)
                            }
                            if let energy = entry.energy {
                                Label(energy.title, systemImage: energy.symbolName)
                                    .foregroundStyle(energy.tint)
                            }
                        }
                        .font(.callout.weight(.semibold))
                        if !entry.win.isEmpty {
                            Label(entry.win, systemImage: "trophy.fill")
                                .foregroundStyle(.primary)
                                .symbolRenderingMode(.multicolor)
                        }
                        if !entry.reflection.isEmpty {
                            Text(entry.reflection)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                if !summary.due.isEmpty || !summary.active.isEmpty {
                    DayGoals(summary: summary)
                }
                if summary.focusSeconds > 0 {
                    FocusTimeline(day: day)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func journalCard<Content: View>(title: String, symbol: String, tint: Color, isEmpty: Bool, empty: String, action: String,
                                            route: SheetRoute, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
                Spacer()
                Button(action) { store.sheet = route }
                    .secondaryActionStyle(tint, compact: true)
            }
            if isEmpty {
                Text(empty)
                    .foregroundStyle(.secondary)
            } else {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: tint, cornerRadius: 22)
    }
}

private struct DayGoals: View {
    @Environment(GoalStore.self) private var store
    let summary: DaySummary

    var body: some View {
        let ids = summary.due + summary.active.filter { !summary.due.contains($0) }
        VStack(alignment: .leading, spacing: 10) {
            Label("Goals", systemImage: "target")
                .font(.headline)
            ForEach(ids.compactMap(store.goal)) { goal in
                let amount = store.engine.amount(for: goal, on: summary.day, now: store.now)
                let met = summary.met.contains(goal.id)
                let due = summary.due.contains(goal.id)
                HStack(spacing: 10) {
                    GoalIcon(goal: goal, size: 26)
                    Text(goal.name)
                        .font(.callout.weight(.medium))
                    Spacer()
                    if amount > 0 {
                        Text(goal.formatLogged(amount))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Image(systemName: met ? "checkmark.circle.fill" : (due ? "circle.dashed" : "plus.circle"))
                        .foregroundStyle(met ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                        .help(met ? "Done" : (due ? "Not done" : "Extra progress"))
                }
                .contentShape(Rectangle())
                .onTapGesture { store.select(goal.id) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }
}
