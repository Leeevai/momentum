// Renders the README screenshots from demo data, without signing or running the app.
// Driven by scripts/screenshots/render.sh, which compiles this file with the app's sources.
import AppKit
import MomentumCore
import SwiftUI
import WidgetKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

/// Demo history is generated relative to now, so "today" always has data.
let demoNow = Date()

@MainActor
func makeStore() -> GoalStore {
    var data = AppData.demo(now: demoNow)
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

@MainActor
func snapshot<V: View>(_ view: V, size: CGSize, dark: Bool, name: String) {
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.backgroundColor = .windowBackgroundColor
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    window.contentView = host
    window.orderFrontRegardless()
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
        .environment(store)
}

/// A screen of the app for a goal matching `pick`, or for a fixed route.
@MainActor
func render(_ name: String, height: CGFloat, dark: Bool, route: (GoalStore) -> Route?) {
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
        let store = makeStore()
        snapshot(MenuBarPanel().environment(store).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 340, height: 560), dark: dark, name: "menubar")
    }
}
