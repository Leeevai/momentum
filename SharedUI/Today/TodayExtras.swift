import MomentumCore
import SwiftUI

// MARK: - Coach

/// Tips from the coach, as a row of glass cards. Each can be acted on or dismissed for the day.
struct CoachStrip: View {
    @Environment(GoalStore.self) private var store
    let tips: [CoachTip]

    var body: some View {
        // Not a glass container: cards that close would blend into one slab of glass.
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(tips) { tip in
                    CoachCard(tip: tip)
                        .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                                                removal: .scale(scale: 0.85).combined(with: .opacity)))
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: tips.map(\.id))
    }
}

private struct CoachCard: View {
    @Environment(GoalStore.self) private var store
    let tip: CoachTip
    @State private var isHovered = false

    var body: some View {
        let tint = color
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tip.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint.gradient))
                    .shadow(color: tint.opacity(0.35), radius: 5, y: 2)
                    .symbolEffect(.bounce, value: isHovered)
                Text(tip.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    withAnimation { store.dismiss(tip) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.35)
                .help("Hide for today")
            }
            Text(tip.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let title = tip.actionTitle {
                Button(title) { store.run(tip) }
                    .primaryActionStyle(tint, compact: true)
            }
        }
        .frame(width: 270, alignment: .leading)
        .frame(minHeight: 132, alignment: .top)
        .glassCard(tint: tint, cornerRadius: 20, padding: 16, highlighted: tip.tone == .urgent)
        .scaleEffect(isHovered ? 1.015 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var color: Color {
        switch tip.tone {
        case .urgent: .orange
        case .positive: .green
        case .neutral: tip.goalID.flatMap(store.goal)?.tint ?? .accentColor
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Today's plan", systemImage: "sun.horizon.fill")
                    .font(.headline)
                    .symbolRenderingMode(.multicolor)
                if !priorities.isEmpty {
                    Text("\(done) of \(priorities.count) priorities done")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button("Edit") { store.sheet = .plan(entry.day) }
                    .secondaryActionStyle(.accentColor, compact: true)
            }
            if !entry.intention.isEmpty {
                Text(entry.intention)
                    .font(.system(.title3, design: .serif).italic())
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Capsule().fill(.orange.gradient).frame(width: 3) }
            }
            if !priorities.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(priorities.enumerated()), id: \.element.id) { index, goal in
                        PriorityChip(goal: goal, rank: index + 1)
                    }
                }
            }
        }
        .glassCard(tint: .orange, cornerRadius: 22)
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
                    GoalRing(goal: goal, lineWidth: 3, showsIcon: false)
                    Image(systemName: isDone ? "checkmark" : "\(rank).circle.fill")
                        .font(.system(size: isDone ? 11 : 13, weight: .bold))
                        .foregroundStyle(goal.tint)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 26, height: 26)
                Text(goal.name)
                    .font(.callout.weight(.semibold))
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(goal.tint.opacity(0.12)))
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
                    Label("Focus timeline", systemImage: "chart.bar.doc.horizontal.fill")
                        .font(.headline)
                    Spacer()
                    if let hovered, let goal = store.goal(hovered.goalID) {
                        Text("\(goal.name) · \(hovered.interval.start.formatted(date: .omitted, time: .shortened))–\(hovered.interval.end.formatted(date: .omitted, time: .shortened)) · \(Formatting.duration(hovered.interval.duration))")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(goal.tint)
                            .transition(.opacity)
                    } else {
                        Text(Formatting.duration(blocks.reduce(0) { $0 + $1.interval.duration }) + " focused")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.primary.opacity(0.06))
                        ForEach(blocks) { block in
                            let x = position(block.interval.start, in: range, width: width)
                            let end = position(block.interval.end, in: range, width: width)
                            let color = store.goal(block.goalID).map { AnyShapeStyle($0.color.linear) } ?? AnyShapeStyle(Color.accentColor)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(color)
                                .overlay {
                                    if block.isLive {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(.white.opacity(0.7), lineWidth: 1.5)
                                    }
                                }
                                .frame(width: max(4, end - x))
                                .offset(x: x)
                                .shadow(color: (store.goal(block.goalID)?.tint ?? .accentColor).opacity(hovered == block ? 0.5 : 0.2), radius: hovered == block ? 6 : 3)
                                .scaleEffect(y: hovered == block ? 1.15 : 1)
                                .onHover { inside in
                                    withAnimation(.easeOut(duration: 0.15)) { hovered = inside ? block : (hovered == block ? nil : hovered) }
                                }
                        }
                        if Calendar.current.isDate(now, inSameDayAs: day) {
                            Capsule()
                                .fill(.red)
                                .frame(width: 2, height: 34)
                                .offset(x: position(now, in: range, width: width) - 1)
                        }
                    }
                }
                .frame(height: 26)
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
        .glassCard(cornerRadius: 22)
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
            HStack(spacing: 22) {
                ProgressRing(progress: over ? 1 : 1 - rest.remaining(at: now) / rest.duration, color: .mint, lineWidth: 10) {
                    Image(systemName: over ? "bell.fill" : (rest.isLong ? "cup.and.saucer.fill" : "leaf.fill"))
                        .font(.system(size: 26))
                        .foregroundStyle(.mint.gradient)
                        .symbolEffect(.bounce, value: over)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text(over ? "Break's over" : (rest.isLong ? "Long break" : "Short break"))
                        .font(.title3.weight(.semibold))
                    if over {
                        Text("Ready for block \(rest.nextBlock) of \(goal.name)?")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(Formatting.clock(rest.remaining(at: now)))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.default, value: Int(now.timeIntervalSince1970))
                            .foregroundStyle(.mint)
                    }
                    BlockDots(done: rest.isLong ? settings.blocksPerCycle : rest.completedBlocks, total: settings.blocksPerCycle)
                }
                Spacer()
                GlassGroup(spacing: 10) {
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
        }
        .glassCard(tint: .mint, cornerRadius: 24, padding: 22, highlighted: true)
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
                    .fill(index < done ? AnyShapeStyle(Color.mint.gradient) : AnyShapeStyle(Color.primary.opacity(0.12)))
                    .frame(width: index < done ? 18 : 10, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: done)
        .accessibilityLabel("\(done) of \(total) blocks done")
    }
}
