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

    private var today: JournalEntry? { entry.data.journalEntry(for: DayID(entry.date)) }

    var body: some View {
        Group {
            if family == .systemSmall {
                small
            } else {
                medium
            }
        }
        .buttonStyle(.plain)
        .widgetBackground(today?.mood?.tint ?? .teal)
    }

    /// The question on one line, and five mood buttons in two rows: short enough for the
    /// smallest widget (an iPhone SE's is 148 points tall).
    private var small: some View {
        let mood = today?.mood
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: mood?.symbolName ?? "cloud.sun.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.headline)
                Text(mood.map { "A \($0.title.lowercased()) day" } ?? "How's today?")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            // Sized for the narrowest small widget (an iPhone SE's, about 116 points inside).
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Mood.allCases.prefix(3)) { moodButton($0, selected: mood, size: 32) }
                }
                HStack(spacing: 6) {
                    ForEach(Mood.allCases.suffix(2)) { moodButton($0, selected: mood, size: 32) }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The question on the left; mood and energy, a row each, on the right.
    private var medium: some View {
        let mood = today?.mood
        let energy = today?.energy
        return HStack(spacing: 12) {
            header
                .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                row("Mood") {
                    ForEach(Mood.allCases) { moodButton($0, selected: mood, size: 29) }
                }
                row("Energy") {
                    ForEach(Energy.allCases) { level in
                        Button(intent: SetEnergyIntent(level)) {
                            circle(level.symbolName, tint: level.tint, title: level.title, selected: level == energy, size: 29)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        let mood = today?.mood
        return VStack(alignment: .leading, spacing: 4) {
            Image(systemName: mood?.symbolName ?? "cloud.sun.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: family == .systemSmall ? 22 : 30))
            Text(mood.map { "A \($0.title.lowercased()) day" } ?? "How's today?")
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(mood == nil ? "Tap to rate it" : "Tap to change")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) { content() }
        }
    }

    private func moodButton(_ choice: Mood, selected: Mood?, size: CGFloat) -> some View {
        Button(intent: SetMoodIntent(choice)) {
            circle(choice.symbolName, tint: choice.tint, title: choice.title, selected: choice == selected, size: size)
        }
    }

    private func circle(_ symbol: String, tint: Color, title: String, selected: Bool, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(selected ? 0.34 : 0.13)))
            .overlay(Circle().strokeBorder(tint.opacity(selected ? 0.85 : 0), lineWidth: 1.5))
            .accessibilityLabel(title)
    }
}
