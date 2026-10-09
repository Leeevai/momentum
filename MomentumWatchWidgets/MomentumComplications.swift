import MomentumCore
import SwiftUI
import WidgetKit

@main
struct MomentumComplications: WidgetBundle {
    var body: some Widget {
        TodayComplication()
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot

    var runningItem: WatchSnapshot.Item? {
        snapshot.session.flatMap { snapshot.item($0.goalID) }
    }

    /// The first goal not done yet, to suggest.
    var nextItem: WatchSnapshot.Item? {
        snapshot.items.first { !$0.isComplete }
    }

    var doneFraction: Double {
        snapshot.total == 0 ? 0 : Double(snapshot.done) / Double(snapshot.total)
    }
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, snapshot: WatchSnapshot(done: 2, total: 5))
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let snapshot = WatchSnapshotStore.load() ?? WatchSnapshot(done: 2, total: 5)
        completion(ComplicationEntry(date: .now, snapshot: snapshot.current(on: DayID(.now))))
    }

    /// The watch app reloads the timeline whenever the iPhone sends a snapshot, and the clocks
    /// run by themselves. Beyond now: when a planned block ends (its clock turns to overtime),
    /// and at midnight, when daily goals start over even if the iPhone hasn't been heard from.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let snapshot = WatchSnapshotStore.load() ?? WatchSnapshot()
        let now = Date.now
        var entries = [ComplicationEntry(date: now, snapshot: snapshot.current(on: DayID(now)))]
        if let end = snapshot.session?.plannedEnd, end > now {
            entries.append(ComplicationEntry(date: end, snapshot: snapshot.current(on: DayID(end))))
        }
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(ComplicationEntry(date: midnight, snapshot: snapshot.current(on: DayID(midnight))))
        }
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Today on the watch face: how many goals are done, or the timer while one runs.
struct TodayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Momentum")
        .description("Today's goals done, or the running timer.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

private struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let session = entry.snapshot.session, let item = entry.runningItem {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: item.symbol)
                        .font(.caption)
                        .widgetAccentable()
                    ComplicationClock(session: session, date: entry.date)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                }
                .padding(4)
            }
        } else {
            Gauge(value: entry.doneFraction) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(entry.snapshot.done)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        }
    }

    private var corner: some View {
        Image(systemName: entry.runningItem?.symbol ?? "flame.fill")
            .font(.title3)
            .widgetAccentable()
            .widgetLabel {
                Gauge(value: entry.doneFraction) {
                    Text("Today")
                } currentValueLabel: {
                    Text("\(entry.snapshot.done)")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("\(entry.snapshot.total)")
                }
            }
    }

    @ViewBuilder
    private var inline: some View {
        if let session = entry.snapshot.session, let item = entry.runningItem {
            // Inline shows a single line of text: one `Text`, not a stack of them.
            Text("\(item.name) ") + ComplicationClock.text(session: session, date: entry.date)
        } else {
            Text("\(entry.snapshot.done) of \(entry.snapshot.total) done")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let session = entry.snapshot.session, let item = entry.runningItem {
                Label(item.name, systemImage: session.isRunning ? item.symbol : "pause.fill")
                    .font(.headline)
                    .widgetAccentable()
                    .lineLimit(1)
                ComplicationClock(session: session, date: entry.date)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
            } else {
                Label("Momentum", systemImage: "flame.fill")
                    .font(.headline)
                    .widgetAccentable()
                Text(entry.snapshot.total == 0 ? "Nothing due today" : "\(entry.snapshot.done) of \(entry.snapshot.total) done")
                    .font(.body.weight(.semibold))
                if let next = entry.nextItem {
                    Text("Next: \(next.name)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The timer on the watch face: counting down a planned block, up otherwise, still when paused.
/// Drawn as of the entry's date, since entries are rendered before they're shown.
private struct ComplicationClock: View {
    let session: FocusSession
    let date: Date

    var body: some View {
        Self.text(session: session, date: date)
            .monospacedDigit()
    }

    static func text(session: FocusSession, date: Date) -> Text {
        if !session.isRunning {
            return Text(Formatting.clock(session.elapsed(at: date)))
        }
        if let end = session.plannedEnd, end > date {
            return Text(timerInterval: date...end, countsDown: true)
        }
        return Text(timerInterval: session.clockStart(at: date)...Date.distantFuture, countsDown: false)
    }
}
