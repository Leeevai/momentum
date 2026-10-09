import MomentumCore
import SwiftUI

/// The past year as a grid of days, a column per week, colored by how much got done or by mood.
struct YearInPixels: View {
    @Environment(GoalStore.self) private var store
    @AppStorage("yearInPixelsShowsMood") private var showsMood = false
    var onSelect: (Date) -> Void = { _ in }

    var body: some View {
        let pixels = store.engine.yearInPixels(endingAt: store.now)
        let weeks = Self.weeks(pixels, firstWeekday: Calendar.current.firstWeekday)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Year in pixels", systemImage: "square.grid.3x3.fill")
                    .font(.headline)
                Spacer()
                Picker("Color by", selection: $showsMood.animation(.easeInOut)) {
                    Text("Progress").tag(false)
                    Text("Mood").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            GeometryReader { proxy in
                let spacing: CGFloat = 2
                let cell = max(3, (proxy.size.width - spacing * CGFloat(weeks.count - 1)) / CGFloat(weeks.count))
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weeks.indices, id: \.self) { column in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { row in
                                if let pixel = weeks[column][row] {
                                    RoundedRectangle(cornerRadius: cell * 0.25, style: .continuous)
                                        .fill(color(for: pixel))
                                        .frame(width: cell, height: cell)
                                        .help(help(for: pixel))
                                        .onTapGesture { onSelect(pixel.day) }
                                } else {
                                    Color.clear.frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
            }
            .aspectRatio(CGFloat(weeks.count) / 7, contentMode: .fit)
            // Hundreds of squares mean nothing read one by one: VoiceOver hears the year at once.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Year in pixels")
            .accessibilityValue(summary(pixels))
            legend
        }
        .glassCard(cornerRadius: 22)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            if showsMood {
                ForEach(Mood.allCases) { mood in
                    Image(systemName: mood.symbolName)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(mood.tint)
                        .help(mood.title)
                }
            } else {
                Text("Less")
                ForEach([0.0, 0.34, 0.67, 1.0], id: \.self) { value in
                    RoundedRectangle(cornerRadius: 2).fill(progressColor(value)).frame(width: 10, height: 10)
                }
                Text("More")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private typealias Pixel = (day: Date, completion: Double?, mood: Mood?)

    /// "212 days with progress, 64 perfect", or how the rated days felt.
    private func summary(_ pixels: [Pixel]) -> String {
        if showsMood {
            let rated = pixels.compactMap(\.mood)
            guard !rated.isEmpty else { return "No days rated yet" }
            let counts = Dictionary(grouping: rated, by: { $0 }).mapValues(\.count)
            let common = counts.max { $0.value < $1.value }?.key
            return "\(rated.count) days rated, most often \(common?.title.lowercased() ?? "")"
        }
        let active = pixels.filter { ($0.completion ?? 0) > 0 }.count
        let perfect = pixels.filter { ($0.completion ?? 0) >= 1 }.count
        return "\(active) days with progress, \(perfect) perfect"
    }

    private func color(for pixel: Pixel) -> Color {
        if showsMood {
            return pixel.mood?.tint ?? .primary.opacity(0.06)
        }
        guard let completion = pixel.completion else { return .primary.opacity(0.04) }
        return progressColor(completion)
    }

    private func progressColor(_ completion: Double) -> Color {
        completion <= 0 ? .primary.opacity(0.08) : Color.green.opacity(0.25 + 0.75 * completion)
    }

    private func help(for pixel: Pixel) -> String {
        var parts = [pixel.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())]
        if let completion = pixel.completion { parts.append(Formatting.percent(completion) + " done") }
        if let mood = pixel.mood { parts.append(mood.title.lowercased()) }
        return parts.joined(separator: ", ")
    }

    /// Days in columns of weeks, padded so each column starts on the first weekday.
    private static func weeks(_ pixels: [Pixel], firstWeekday: Int) -> [[Pixel?]] {
        guard let first = pixels.first else { return [] }
        let leading = (Calendar.current.component(.weekday, from: first.day) - firstWeekday + 7) % 7
        let padded: [Pixel?] = Array(repeating: nil, count: leading) + pixels.map { Optional($0) }
        return stride(from: 0, to: padded.count, by: 7).map { start in
            let column = Array(padded[start..<min(start + 7, padded.count)])
            return column + Array(repeating: nil, count: 7 - column.count)
        }
    }
}
