// Renders every widget at each size into one gallery image per appearance.
import AppKit
import MomentumCore
import SwiftUI
import WidgetKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])

MainActor.assumeIsolated {
    var data = AppData.demo()
    if let deepWork = data.goals.first(where: { $0.name == "Deep work" }) {
        data.session = FocusSession(goalID: deepWork.id, plannedDuration: 50 * 60, start: Date().addingTimeInterval(-32 * 60))
    }
    let engine = ProgressEngine(data: data)
    let books = data.goals.first { $0.kind == .books }?.id
    let entry = MomentumEntry(date: .now, engine: engine)
    let bookEntry = MomentumEntry(date: .now, engine: engine, goalID: books)
    let spanish = data.goals.first { $0.challenge != nil }?.id
    let challengeEntry = MomentumEntry(date: .now, engine: engine, goalID: spanish)
    let small = CGSize(width: 170, height: 170), medium = CGSize(width: 364, height: 170), large = CGSize(width: 364, height: 382)

    func tile<V: View>(_ view: V, _ size: CGSize, tint: Color) -> some View {
        view
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    for dark in [false, true] {
        let gallery = VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 22) {
                tile(TodayWidgetView(family: .systemSmall, entry: entry), small, tint: .blue)
                tile(TodayWidgetView(family: .systemMedium, entry: entry), medium, tint: .blue)
                tile(FocusWidgetView(family: .systemSmall, entry: entry), small, tint: .indigo)
            }
            HStack(alignment: .top, spacing: 22) {
                tile(GoalWidgetView(family: .systemLarge, entry: entry), large, tint: .indigo)
                tile(TodayWidgetView(family: .systemLarge, entry: entry), large, tint: .blue)
            }
            HStack(alignment: .top, spacing: 22) {
                tile(GoalWidgetView(family: .systemMedium, entry: bookEntry), medium, tint: .orange)
                tile(StreaksWidgetView(family: .systemMedium, entry: entry), medium, tint: .orange)
            }
            HStack(alignment: .top, spacing: 22) {
                tile(GoalWidgetView(family: .systemSmall, entry: bookEntry), small, tint: .orange)
                tile(FocusWidgetView(family: .systemMedium, entry: entry), medium, tint: .indigo)
                tile(StreaksWidgetView(family: .systemSmall, entry: entry), small, tint: .orange)
            }
            HStack(alignment: .top, spacing: 22) {
                tile(ChallengeWidgetView(family: .systemSmall, entry: challengeEntry), small, tint: .red)
                tile(ChallengeWidgetView(family: .systemMedium, entry: challengeEntry), medium, tint: .red)
                tile(GoalWidgetView(family: .systemSmall, entry: challengeEntry), small, tint: .red)
            }
            HStack(alignment: .top, spacing: 22) {
                tile(MoodWidgetView(family: .systemSmall, entry: entry), small, tint: .teal)
                tile(MoodWidgetView(family: .systemMedium, entry: entry), medium, tint: .teal)
            }
            HStack(alignment: .top, spacing: 22) {
                tile(WeekWidgetView(family: .systemSmall, entry: entry), small, tint: .indigo)
                tile(WeekWidgetView(family: .systemMedium, entry: entry), medium, tint: .indigo)
            }
        }
        .padding(34)
        .background(LinearGradient(colors: dark ? [Color(white: 0.10), Color(white: 0.18)] : [Color(red: 0.86, green: 0.90, blue: 0.98), Color(red: 0.96, green: 0.90, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .environment(\.colorScheme, dark ? .dark : .light)

        let renderer = ImageRenderer(content: gallery)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { continue }
        let file = output.appendingPathComponent("widgets-\(dark ? "dark" : "light").png")
        try? png.write(to: file)
        print("wrote", file.lastPathComponent)
    }
}

/// `ImageRenderer` cannot draw `Link`; in this harness module this plain stand-in shadows it.
struct Link<Label: View>: View {
    let label: Label

    init(destination: URL, @ViewBuilder label: () -> Label) {
        self.label = label()
    }

    var body: some View { label }
}
