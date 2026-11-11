import MomentumCore
import SwiftUI

// MARK: - Coach

/// Tips from the coach, as rows in one pane. Each can be acted on or dismissed for the day.
struct CoachStrip: View {
    @Environment(GoalStore.self) private var store
    let tips: [CoachTip]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Suggestions")
            VStack(spacing: 0) {
                ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                    if index > 0 { Divider() }
                    CoachRow(tip: tip)
                        .transition(.opacity)
                }
            }
            .glassCard(padding: 0)
        }
        .animation(.easeOut(duration: 0.2), value: tips.map(\.id))
    }
}

private struct CoachRow: View {
    @Environment(GoalStore.self) private var store
    let tip: CoachTip
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: tip.symbol)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(tip.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let title = tip.actionTitle {
                Button(title) { store.run(tip) }
                    .secondaryActionStyle(color, compact: true)
            }
            Button {
                withAnimation { store.dismiss(tip) }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Hide for today")
            .accessibilityLabel("Hide for today")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Urgent tips in the attention color, good news in success, others in their goal's.
    private var color: Color {
        switch tip.tone {
        case .urgent: .attention
        case .positive: .success
        case .neutral: tip.goalID.flatMap(store.goal)?.tint ?? .accent
        }
    }
}

// MARK: - Plan

/// The day's intention and priorities, once planned.
struct DayPlanCard: View {
    @Environment(GoalStore.self) private var store
    let entry: JournalEntry

    var body: some View {
        let engine = store.engine
        let now = store.now
        let priorities = entry.priorities.compactMap(store.goal)
        let done = priorities.filter { engine.isComplete($0, now: now) }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's plan")
                    .paneTitleStyle()
                if !priorities.isEmpty {
                    Text("\(done) of \(priorities.count) done")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button("Edit") { store.sheet = .plan(entry.day) }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
            if !entry.intention.isEmpty {
                Text(entry.intention)
                    .font(.system(.title3, design: .serif).italic())
            }
            if !priorities.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(Array(priorities.enumerated()), id: \.element.id) { index, goal in
                        PriorityChip(goal: goal, rank: index + 1)
                    }
                }
            }
        }
        .glassCard()
    }
}

private struct PriorityChip: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let rank: Int

    var body: some View {
        let isDone = store.engine.isComplete(goal, now: store.now)
        Button {
            store.select(goal.id)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    GoalRing(goal: goal, lineWidth: 2.5, showsIcon: false)
                    Group {
                        if isDone {
                            Image(systemName: "checkmark")
                        } else {
                            Text("\(rank)")
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 22, height: 22)
                Text(goal.name)
                    .font(.callout)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isDone)
    }
}

// MARK: - Timeline

/// Today's focus sessions on a strip from morning to night.
struct FocusTimeline: View {
    @Environment(GoalStore.self) private var store
    var day: Date = .now
    @State private var hovered: TimelineBlock?

    var body: some View {
        LiveClock(isLive: store.data.session?.isRunning == true && Calendar.current.isDateInToday(day), fallback: store.now) { now in
            let blocks = store.engine.timeline(on: day, now: now)
            let range = visibleRange(blocks, now: now)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Focus timeline")
                        .paneTitleStyle()
                    Spacer()
                    if let hovered, let goal = store.goal(hovered.goalID) {
                        Text("\(goal.name) · \(hovered.interval.start.formatted(date: .omitted, time: .shortened))–\(hovered.interval.end.formatted(date: .omitted, time: .shortened)) · \(Formatting.duration(hovered.interval.duration))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    } else {
                        Text(Formatting.duration(blocks.reduce(0) { $0 + $1.interval.duration }) + " focused")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.primary.opacity(0.05))
                        ForEach(blocks) { block in
                            let x = position(block.interval.start, in: range, width: width)
                            let end = position(block.interval.end, in: range, width: width)
                            let color = store.goal(block.goalID).map { AnyShapeStyle($0.color.swatch) } ?? AnyShapeStyle(Color.accent)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color)
                                .opacity(hovered == nil || hovered == block ? 1 : 0.5)
                                .frame(width: max(4, end - x))
                                .offset(x: x)
                                .onHover { inside in
                                    withAnimation(.easeOut(duration: 0.15)) { hovered = inside ? block : (hovered == block ? nil : hovered) }
                                }
                        }
                        if Calendar.current.isDate(now, inSameDayAs: day) {
                            Capsule()
                                .fill(Color.primary.opacity(0.5))
                                .frame(width: 1.5, height: 26)
                                .offset(x: position(now, in: range, width: width) - 0.75)
                        }
                    }
                }
                .frame(height: 18)
                HStack {
                    ForEach(ticks(range), id: \.self) { tick in
                        Text(tick, format: .dateTime.hour())
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if tick != ticks(range).last { Spacer(minLength: 0) }
                    }
                }
            }
        }
        .glassCard()
    }

    /// From the earlier of 8:00 and the first block, to the later of 20:00 and the last block or now.
    private func visibleRange(_ blocks: [TimelineBlock], now: Date) -> DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        func hour(_ h: Int) -> Date { calendar.date(byAdding: .hour, value: h, to: start) ?? start }
        let firstHour = blocks.first.map { calendar.component(.hour, from: $0.interval.start) } ?? 8
        let lastEnd = max(blocks.map(\.interval.end).max() ?? start, calendar.isDate(now, inSameDayAs: day) ? now : start)
        let lastHour = calendar.component(.hour, from: lastEnd) + 1
        let from = hour(min(8, firstHour))
        let to = hour(min(24, max(20, lastHour)))
        return DateInterval(start: from, end: max(to, from.addingTimeInterval(3600)))
    }

    private func position(_ date: Date, in range: DateInterval, width: CGFloat) -> CGFloat {
        CGFloat(min(1, max(0, date.timeIntervalSince(range.start) / range.duration))) * width
    }

    private func ticks(_ range: DateInterval) -> [Date] {
        let hours = Int(range.duration / 3600)
        let step = hours > 12 ? 3 : 2
        return stride(from: 0, through: hours, by: step).map { range.start.addingTimeInterval(Double($0) * 3600) }
    }
}

// MARK: - Pomodoro break

/// A break between Pomodoro blocks: counts down, then offers the next block.
struct RestBanner: View {
    @Environment(GoalStore.self) private var store
    let rest: RestPeriod
    let goal: Goal

    var body: some View {
        let settings = store.data.preferences.pomodoro
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let over = rest.isOver(at: now)
            HStack(spacing: 20) {
                ProgressRing(progress: over ? 1 : 1 - rest.remaining(at: now) / rest.duration, color: .mint, lineWidth: 7) {
                    Image(systemName: over ? "bell" : (rest.isLong ? "cup.and.saucer" : "leaf"))
                        .font(.system(size: 20))
                        .foregroundStyle(Color.rest)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(over ? "Break's over" : (rest.isLong ? "Long break" : "Short break"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    if over {
                        Text("Ready for block \(rest.nextBlock) of \(goal.name)?")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(Formatting.clock(rest.remaining(at: now)))
                            .font(.system(size: 32, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .clockTick(now)
                    }
                    BlockDots(done: rest.isLong ? settings.blocksPerCycle : rest.completedBlocks, total: settings.blocksPerCycle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    Button {
                        store.startNextBlock()
                    } label: {
                        Label("Start block \(rest.nextBlock)", systemImage: "play.fill")
                    }
                    .primaryActionStyle(goal.tint)
                    Button {
                        store.endRest()
                    } label: {
                        Label(over ? "Done for now" : "Skip break", systemImage: over ? "checkmark" : "forward.end.fill")
                    }
                    .secondaryActionStyle(.secondary, compact: true)
                }
            }
        }
        .glassCard(tint: .rest, highlighted: true)
    }
}

/// Filled dots for blocks done in the current Pomodoro cycle.
struct BlockDots: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < done ? AnyShapeStyle(Color.rest) : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .frame(width: 12, height: 4)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: done)
        .accessibilityLabel("\(done) of \(total) blocks done")
    }
}
