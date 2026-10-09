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

extension DateInterval {
    /// Whether `date` falls in `[start, end)`. `contains(_:)` includes the end, which makes a
    /// moment on a boundary (midnight, the first of the year) belong to two adjacent periods.
    func holds(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
