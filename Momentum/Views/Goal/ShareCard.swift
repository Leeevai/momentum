import AppKit
import MomentumCore
import SwiftUI
import UniformTypeIdentifiers

/// A self-contained image of a goal's progress: ring, streak, key numbers and history.
/// Pure SwiftUI shapes and text, so `ImageRenderer` draws it faithfully.
struct ShareCard: View {
    let goal: Goal
    let engine: ProgressEngine
    let now: Date

    var body: some View {
        let streak = engine.streak(for: goal, now: now)
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: goal.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .frame(width: 60, height: 60)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(goal.targetDescription)
                        .font(.system(size: 15, weight: .medium))
                        .opacity(0.8)
                }
                Spacer()
            }
            HStack(alignment: .center, spacing: 28) {
                ZStack {
                    Circle().stroke(.white.opacity(0.22), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: max(0.001, engine.progress(for: goal, now: now)))
                        .stroke(.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(goal.formatShort(engine.currentAmount(for: goal, now: now)))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(goal.effectivePeriod.currentLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .textCase(.uppercase)
                            .opacity(0.8)
                    }
                }
                .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 14) {
                    figure("\(streak.current)", "\(streak.unit) streak", symbol: "flame.fill")
                    figure("\(streak.best)", "best streak", symbol: "trophy.fill")
                    if let rate = engine.completionRate(for: goal, now: now) {
                        figure(Formatting.percent(rate), "hit rate", symbol: "target")
                    } else {
                        figure(lifetimeText, goal.kind == .books ? "pages read" : "all time", symbol: goal.kind == .books ? "book.pages.fill" : "sum")
                    }
                }
                Spacer()
            }
            ShareHeatmap(engine: engine, goal: goal, now: now)
                .frame(height: 7 * 13 + 6 * 3)
            HStack {
                Text("Tracked with Momentum")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(now, format: .dateTime.month(.wide).day().year())
                    .font(.system(size: 12, weight: .medium))
            }
            .opacity(0.75)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(width: 620)
        .background(
            LinearGradient(colors: [goal.tint.blended(with: .white, by: 0.1), goal.tint.blended(with: .black, by: 0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    /// Books log pages, so their lifetime figure is pages read rather than books.
    private var lifetimeText: String {
        let lifetime = engine.lifetimeAmount(for: goal, now: now)
        return goal.kind == .books ? Formatting.number(lifetime) : goal.format(lifetime)
    }

    private func figure(_ value: String, _ label: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(label).font(.system(size: 12, weight: .medium)).opacity(0.8)
            }
        }
    }

    /// Renders the card at 2x for crisp sharing.
    @MainActor
    static func image(for goal: Goal, engine: ProgressEngine, now: Date = .now) -> NSImage? {
        let renderer = ImageRenderer(content: ShareCard(goal: goal, engine: engine, now: now).environment(\.colorScheme, .dark))
        renderer.scale = 2
        return renderer.nsImage
    }
}

/// The heatmap in white on the card's color.
private struct ShareHeatmap: View {
    let engine: ProgressEngine
    let goal: Goal
    let now: Date

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 3
            let cell = min(13, (geometry.size.height - spacing * 6) / 7)
            let count = max(1, Int((geometry.size.width + spacing) / (cell + spacing)))
            let weeks = Heatmap.weeks(count, endingAt: now, engine: engine)
            HStack(spacing: spacing) {
                ForEach(weeks.indices, id: \.self) { column in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { row in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(.white.opacity(opacity(weeks[column][row])))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func opacity(_ day: Date?) -> Double {
        guard let day else { return 0 }
        let intensity = engine.intensity(for: goal, on: day, now: now)
        return intensity > 0 ? 0.35 + 0.65 * intensity : 0.12
    }
}

/// Preview of the share card with save, copy and share actions.
struct ShareCardSheet: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let goal: Goal
    @State private var image: NSImage?
    @State private var status: String?

    var body: some View {
        VStack(spacing: 18) {
            Text("Share your progress")
                .font(.title2.weight(.bold))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 520)
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            } else {
                ProgressView().frame(height: 300)
            }
            if let status {
                Text(status).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    copy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .secondaryActionStyle(goal.tint)
                Button {
                    save()
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
                .secondaryActionStyle(goal.tint)
                if let image {
                    ShareLink(item: Image(nsImage: image), preview: SharePreview(goal.name, image: Image(nsImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .primaryActionStyle(goal.tint)
                }
            }
        }
        .padding(24)
        .frame(width: 600)
        .task { image = ShareCard.image(for: goal, engine: store.engine) }
    }

    private func copy() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        status = "Copied. Paste it anywhere."
    }

    private func save() {
        guard let image, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(goal.name) progress.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            status = "Saved to \(url.lastPathComponent)."
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
