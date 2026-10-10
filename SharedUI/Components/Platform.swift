import MomentumCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A link's icon: the app that opens it on a Mac, a symbol on iPhone.
struct LinkIcon: View {
    let link: GoalLink
    var size: CGFloat = 28
    @Environment(\.self) private var environment

    var body: some View {
        #if os(macOS)
        Image(nsImage: LinkOpener.icon(for: link))
            .resizable()
            .frame(width: size, height: size)
        #else
        Image(systemName: link.isFile ? "doc.fill" : "safari.fill")
            .font(.system(size: size * 0.6))
            .foregroundStyle(Color.accent.foreground(in: environment))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color.accent.gradient))
        #endif
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

#if os(iOS)
extension LinkOpener {
    /// Files picked on iPhone are opened by URL; there's no sandbox bookmark to keep.
    static func bookmark(for url: URL) -> Data? { nil }

    @MainActor
    static func openFocusLinks(of goal: Goal) {}
}
#endif

extension View {
    /// A sheet's size on a Mac; on iPhone and iPad sheets size themselves.
    @ViewBuilder
    func sheetFrame(width: CGFloat, height: CGFloat? = nil) -> some View {
        #if os(macOS)
        frame(width: width, height: height)
        #else
        self
        #endif
    }
}

enum Metrics {
    /// Space around a screen's content: roomy on a Mac, tighter on a phone.
    static var screenPadding: CGFloat {
        #if os(macOS)
        28
        #else
        16
        #endif
    }

    /// Whether screens show their own large title (the Mac), rather than the navigation bar's.
    static var showsInlineTitles: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// "Click" on a Mac, "Tap" on a touch screen, for hints that name the gesture.
    static var tapVerb: String {
        #if os(macOS)
        "Click"
        #else
        "Tap"
        #endif
    }
}

/// A file to save through `fileExporter`: a JSON backup or a CSV of entries.
struct ExportDocument: FileDocument {
    enum Kind {
        /// Everything, as JSON that imports back.
        case backup
        /// Every entry, as a spreadsheet.
        case entries
    }

    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    private let source: AppData?
    private let kind: Kind
    private var contents: Data?

    /// A document made from `data` only when it's saved: building it encodes the whole history,
    /// too slow to do each time the screen offering it redraws.
    init(_ data: AppData, kind: Kind) {
        source = data
        self.kind = kind
    }

    init(configuration: ReadConfiguration) throws {
        source = nil
        contents = configuration.file.regularFileContents ?? Data()
        kind = configuration.contentType == .commaSeparatedText ? .entries : .backup
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let contents { return FileWrapper(regularFileWithContents: contents) }
        guard let source else { return FileWrapper(regularFileWithContents: Data()) }
        let data = switch kind {
        case .backup: try FileStore.encode(source, pretty: true)
        case .entries: Data(CSVExporter.csv(for: source).utf8)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
