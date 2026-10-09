import AppIntents
import MomentumCore
import SwiftUI
import WidgetKit

/// How today feels, rated with one tap: mood, and on the medium size energy too. Each tap goes
/// into the day's journal entry.
struct MoodWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Mood", provider: TodayProvider()) { entry in
            MoodWidgetView(entry: entry)
                .widgetURL(DeepLink.journal.url)
        }
        .configurationDisplayName("Mood")
        .description("Rate how today feels, and your energy, in one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MoodWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MomentumEntry

    var body: some View {
        let today = entry.data.journalEntry(for: DayID(entry.date))
        let mood = today?.mood
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: mood?.symbolName ?? "cloud.sun")
                    .symbolRenderingMode(.multicolor)
                    .font(.title3)
                Text(mood.map { "A \($0.title.lowercased()) day" } ?? "How's today?")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            row(Mood.allCases, selected: mood) { choice in
                Button(intent: SetMoodIntent(choice)) {
                    label(symbol: choice.symbolName, tint: choice.tint, title: choice.title, selected: choice == mood)
                }
            }
            if family != .systemSmall {
                row(Energy.allCases, selected: today?.energy) { level in
                    Button(intent: SetEnergyIntent(level)) {
                        label(symbol: level.symbolName, tint: level.tint, title: level.title, selected: level == today?.energy)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .widgetBackground(mood?.tint ?? .teal)
    }

    private func row<Item: Identifiable & Equatable, Content: View>(_ items: [Item], selected: Item?, @ViewBuilder button: @escaping (Item) -> Content) -> some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                button(item)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func label(symbol: String, tint: Color, title: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: family == .systemSmall ? 14 : 15, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: family == .systemSmall ? 26 : 30, height: family == .systemSmall ? 26 : 30)
            .background(Circle().fill(tint.opacity(selected ? 0.32 : 0.12)))
            .overlay(Circle().strokeBorder(tint.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
            .accessibilityLabel(title)
    }
}
