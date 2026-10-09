import Foundation

extension KeyedDecodingContainer {
    /// Decodes a value that may be missing from older files, falling back to `defaultValue`.
    ///
    /// Every persisted type decodes through this so that adding a field never makes an existing
    /// data file unreadable.
    func decode<T: Decodable>(_ key: Key, default defaultValue: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? defaultValue()
    }

    /// Decodes an array, skipping elements that fail to decode (written by a newer version, or
    /// damaged) instead of failing the whole file. A missing key is an empty array.
    func decodeLossy<T: Decodable>(_ key: Key) throws -> [T] {
        guard contains(key) else { return [] }
        return try decode([Lossy<T>].self, forKey: key).compactMap(\.value)
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension DateInterval {
    /// Whether `date` falls in `[start, end)`. `contains(_:)` includes the end, which makes a
    /// moment on a boundary (midnight, the first of the year) belong to two adjacent periods.
    func holds(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
