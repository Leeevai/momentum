import AppKit
import Carbon.HIToolbox
import MomentumCore
import SwiftUI

// MARK: - Panel

/// A floating quick-actions panel, summoned from any app with a global shortcut: type a goal,
/// press Return, and you're back where you were with the timer running.
@MainActor
final class QuickPanelController {
    static let shared = QuickPanelController()

    private weak var store: GoalStore?
    private var panel: QuickPanel?

    func attach(_ store: GoalStore) {
        self.store = store
        GlobalHotKey.shared.action = { [weak self] in self?.toggle() }
        GlobalHotKey.shared.register(HotKeyCombo.saved)
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    func show() {
        guard let store else { return }
        close()
        let panel = QuickPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 460))
        let root = QuickActionsView(onClose: { [weak self] in self?.close() }, onOpenApp: { [weak self] in
            self?.close()
            NotificationCenter.default.post(name: .reopenMainWindow, object: nil)
            NSApp.activate()
        })
        .storePalette()
        .environment(store)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        let host = NSHostingView(rootView: root)
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = host
        panel.positionOnActiveScreen()
        panel.onResignKey = { [weak self] in self?.close() }
        self.panel = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.onResignKey = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

/// A borderless panel that takes typing without activating the app, and floats over everything.
final class QuickPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Centered horizontally, a little above the middle of the screen with the mouse.
    func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = CGPoint(x: visible.midX - frame.width / 2, y: visible.minY + visible.height * 0.62 - frame.height / 2)
        setFrameOrigin(origin)
    }
}

/// Liquid Glass on macOS 26, a HUD material before.
private struct PanelBackground: View {
    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            VisualEffect()
        }
        #else
        VisualEffect()
        #endif
    }

    private struct VisualEffect: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .hudWindow
            view.blendingMode = .behindWindow
            view.state = .active
            return view
        }

        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
    }
}

// MARK: - Global shortcut

/// A key and modifiers, stored in user defaults: a per-Mac preference, like any shortcut.
struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32
    /// The key's character, for display.
    var key: String

    /// ⌃⌥M: M for Momentum, and free in macOS and common apps.
    static let standard = HotKeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey), key: "M")

    private static let defaultsKey = "quickPanelHotKey"
    private static let disabledKey = "quickPanelHotKeyDisabled"

    /// The saved shortcut; nil when turned off.
    static var saved: HotKeyCombo? {
        if UserDefaults.standard.bool(forKey: disabledKey) { return nil }
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data) else { return standard }
        return combo
    }

    @MainActor
    static func save(_ combo: HotKeyCombo?) {
        let defaults = UserDefaults.standard
        defaults.set(combo == nil, forKey: disabledKey)
        if let combo, let data = try? JSONEncoder().encode(combo) { defaults.set(data, forKey: defaultsKey) }
        GlobalHotKey.shared.register(combo)
    }

    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    /// A combo from a key press, if it has a modifier that makes it safe as a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        let character = event.charactersIgnoringModifiers?.uppercased() ?? ""
        let key: String = switch Int(event.keyCode) {
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        default: character.isEmpty ? "?" : character
        }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, key: key)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }
}

/// Registers one system-wide shortcut with Carbon, the API macOS still uses for them; it
/// needs no accessibility permission and works in the sandbox.
@MainActor
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var action: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ combo: HotKeyCombo?) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        guard let combo else { return }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x4D4F4D54), id: 1) // "MOMT"
        RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func installHandler() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotKey.shared.action?() }
            }
            return noErr
        }, 1, &type, nil, &handler)
    }
}

/// Records a global shortcut: click, then press the keys. Escape cancels; Delete turns it off.
struct HotKeyRecorder: View {
    @State private var combo = HotKeyCombo.saved
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Type a shortcut…" : (combo?.displayString ?? "Off"))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(minWidth: 120)
            }
            .secondaryActionStyle(isRecording ? .orange : .accent, compact: true)
            if combo != nil && !isRecording {
                Button {
                    combo = nil
                    HotKeyCombo.save(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Turn off")
            }
            if combo != .standard && !isRecording {
                Button("Default") {
                    combo = .standard
                    HotKeyCombo.save(.standard)
                }
                .buttonStyle(.link)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        GlobalHotKey.shared.register(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                stop()
            case kVK_Delete, kVK_ForwardDelete:
                combo = nil
                stop()
            default:
                guard let recorded = HotKeyCombo(event: event) else {
                    NSSound.beep()
                    return nil
                }
                combo = recorded
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { HotKeyCombo.save(combo) }
        isRecording = false
    }
}
