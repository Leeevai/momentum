import Foundation
import MomentumCore
import SwiftUI
#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(AppKit)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

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
    private static let memory = NSCache<NSString, PlatformImage>()

    static func image(for book: Book) -> PlatformImage? {
        guard book.coverURL != nil else { return nil }
        let key = book.id.uuidString as NSString
        if let cached = memory.object(forKey: key) { return cached }
        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: fileURL(for: book.id)) else { return nil }
        #else
        guard let image = UIImage(contentsOfFile: fileURL(for: book.id).path) else { return nil }
        #endif
        memory.setObject(image, forKey: key)
        return image
    }

    static func hasCover(for book: Book) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: book.id).path)
    }
}
