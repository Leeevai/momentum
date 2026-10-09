import AppKit
import Foundation
import MomentumCore

/// Book covers saved in the app group, so widgets (which can't download) can show them and the
/// app can show them offline. The app fills it; anyone can read it.
enum CoverCache {
    static var directoryURL: URL {
        SharedStore.directoryURL.appendingPathComponent("Covers", isDirectory: true)
    }

    static func fileURL(for bookID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(bookID.uuidString).jpg")
    }

    /// Decoded covers, so views don't read the file on every render.
    private static let memory = NSCache<NSString, NSImage>()

    static func image(for book: Book) -> NSImage? {
        guard book.coverURL != nil else { return nil }
        let key = book.id.uuidString as NSString
        if let cached = memory.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: fileURL(for: book.id)) else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    static func hasCover(for book: Book) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: book.id).path)
    }
}
