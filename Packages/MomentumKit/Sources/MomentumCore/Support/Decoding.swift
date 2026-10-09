import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value that may be missing from older files, falling back to `defaultValue`.
    ///
    /// Every persisted type decodes through this so that adding a field never makes an existing
    /// data file unreadable.
    func decode<T: Decodable>(_ key: Key, default defaultValue: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? defaultValue()
    }
}
