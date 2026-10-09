// Renders the README screenshots from demo data, without signing or running the app.
// Driven by scripts/screenshots/render.sh, which compiles this file with the app's sources.
import AppKit
import MomentumCore
import SwiftUI
import WidgetKit

nonisolated(unsafe) var output = URL(fileURLWithPath: CommandLine.arguments[1])
let app = NSApplication.shared
app.setActivationPolicy(.regular)
// Screenshots show a returning user: no first-run tip. Registered defaults stay in memory.
UserDefaults.standard.register(defaults: ["dismissedWidgetTip": true])

/// Demo history is generated relative to now, so "today" always has data.
let demoNow = Date()

@MainActor
func makeStore() -> GoalStore {
    var data = AppData.demo(now: demoNow)
    // MOMENTUM_PALETTE=ocean renders in another palette.
    if let name = ProcessInfo.processInfo.environment["MOMENTUM_PALETTE"], let palette = ThemePalette(rawValue: name) {
        data.preferences.palette = palette
    }
    // A focus session in progress on Deep work, 32 minutes into 50.
    if let deepWork = data.goals.first(where: { $0.name == "Deep work" }) {
        data.session = FocusSession(goalID: deepWork.id, plannedDuration: 50 * 60, start: Date().addingTimeInterval(-32 * 60))
        data.session?.note = "Polishing the widget timelines"
    }
    return GoalStore.preview(data)
}

/// `CGWindowListCreateImage`, looked up at run time: the Swift overlay marks it unavailable on
/// recent SDKs, but it still captures a process's own windows without Screen Recording access.
typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let windowImage: WindowImageFunction = {
    let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
    return unsafeBitCast(dlsym(handle, "CGWindowListCreateImage"), to: WindowImageFunction.self)
}()

/// A borderless window that can become key, so controls and glass render in their active state.
final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
func snapshot<V: View>(_ view: V, size: CGSize, dark: Bool, name: String) {
    let window = KeyWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.backgroundColor = .windowBackgroundColor
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    // Let layout, images and tasks settle.
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    // kCGWindowListOptionIncludingWindow = 1 << 3; kCGWindowImageBoundsIgnoreFraming | BestResolution.
    guard let image = windowImage(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue() else {
        print("could not capture", name)
        return
    }
    let file = output.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
    window.orderOut(nil)
    print("wrote", file.lastPathComponent, image.width, "x", image.height)
}

@MainActor
func screen(_ store: GoalStore, route: Route) -> some View {
    store.route = route
    return RootView()
        .storePalette()
        .environment(store)
}

/// A screen of the app for a goal matching `pick`, or for a fixed route.
@MainActor
func render(_ name: String, height: CGFloat, dark: Bool, route: (GoalStore) -> Route?) {
    guard isWanted(name) else { return }
    let store = makeStore()
    guard let destination = route(store) else { return }
    snapshot(screen(store, route: destination), size: CGSize(width: 1280, height: height), dark: dark, name: name)
}

MainActor.assumeIsolated {
    for dark in [false, true] {
        render("today", height: 860, dark: dark) { _ in .today }
        render("goal-time", height: 1500, dark: dark) { store in store.data.goals.first { $0.name == "Deep work" }.map { .goal($0.id) } }
        render("goal-books", height: 1500, dark: dark) { store in store.data.goals.first { $0.kind == .books }.map { .goal($0.id) } }
        render("goal-milestones", height: 1100, dark: dark) { store in store.data.goals.first { $0.kind == .milestones }.map { .goal($0.id) } }
        render("insights", height: 1200, dark: dark) { _ in .insights }
        render("journal", height: 960, dark: dark) { _ in .journal }
        render("awards", height: 1300, dark: dark) { _ in .awards }
        let store = makeStore()
        if isWanted("menubar") {
            snapshot(MenuBarPanel().storePalette().environment(store).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 340, height: 560), dark: dark, name: "menubar")
        }
    }
    // Sheets and Settings, for review rather than the README: written only when asked for.
    if CommandLine.arguments.count > 2 {
        let extras = URL(fileURLWithPath: CommandLine.arguments[2])
        let store = makeStore()
        let deepWork = store.data.goals[0]
        let books = store.data.goals.first { $0.kind == .books }!
        let sheets: [(String, AnyView, CGSize)] = [
            ("sheet-quick-actions", AnyView(QuickActionsView()), CGSize(width: 580, height: 440)),
            ("sheet-new-goal", AnyView(NewGoalFlow()), CGSize(width: 640, height: 620)),
            ("sheet-editor", AnyView(GoalEditor(goal: deepWork, isNew: false)), CGSize(width: 580, height: 720)),
            ("sheet-log", AnyView(LogProgressSheet(goal: store.data.goals.first { $0.kind == .amount }!)), CGSize(width: 440, height: 400)),
            ("sheet-book", AnyView(BookEditor(goalID: books.id, book: books.books.first { $0.status == .reading })), CGSize(width: 480, height: 600)),
            ("sheet-link", AnyView(LinkEditor(goalID: deepWork.id, link: deepWork.links.first)), CGSize(width: 460, height: 330)),
            ("settings", AnyView(SettingsView()), CGSize(width: 500, height: 600)),
            ("sheet-plan", AnyView(PlanSheet(day: DayID(.now))), CGSize(width: 560, height: 620)),
            ("sheet-review", AnyView(WeekReviewSheet()), CGSize(width: 560, height: 680)),
            ("sheet-reflect", AnyView(ReflectSheet(day: DayID(.now))), CGSize(width: 520, height: 720)),
        ]
        for goal in [deepWork, books] {
            if let image = ShareCard.image(for: goal, engine: store.engine), let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: extras.appendingPathComponent("share-\(goal.kind.rawValue).png"))
                print("wrote share-\(goal.kind.rawValue).png")
            }
        }
        if let image = WeekShareCard.image(review: store.engine.weekReview(endingAt: .now), goals: store.data.goals),
           let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: extras.appendingPathComponent("share-week.png"))
            print("wrote share-week.png")
        }
        withExtrasOutput(extras) {
            render("goal-challenge", height: 1300, dark: true) { store in store.data.goals.first { $0.challenge != nil }.map { .goal($0.id) } }
            let rated = makeStore()
            rated.sessionRating = SessionRating(goal: rated.data.goals[0], entryIDs: [], seconds: 50 * 60)
            snapshot(screen(rated, route: .today), size: CGSize(width: 1280, height: 860), dark: false, name: "today-rating")
        }
        for (name, view, size) in sheets {
            let original = output
            withExtrasOutput(extras) {
                snapshot(view.storePalette().environment(store).background(Color(nsColor: .windowBackgroundColor)), size: size, dark: false, name: name)
            }
            _ = original
        }
    }
}

/// Whether `name` is among the screens asked for in MOMENTUM_SHOTS (a comma-separated list), or
/// no list was given.
func isWanted(_ name: String) -> Bool {
    guard let list = ProcessInfo.processInfo.environment["MOMENTUM_SHOTS"], !list.isEmpty else { return true }
    return list.split(separator: ",").contains { $0 == name }
}

/// Points `snapshot` at another folder for the duration of `body`.
@MainActor
func withExtrasOutput(_ folder: URL, _ body: () -> Void) {
    let saved = output
    output = folder
    body()
    output = saved
}
