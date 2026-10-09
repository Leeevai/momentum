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

/// The stretches of two arrays between their common start and common end. Anything outside
/// them is the same element in the same place in both, so a diff by id need only look inside:
/// with thousands of entries and one added, that is the difference between a scan and a sort.
func changedStretch<T: Equatable>(_ a: [T], _ b: [T]) -> (ArraySlice<T>, ArraySlice<T>) {
    var start = 0
    let shorter = min(a.count, b.count)
    while start < shorter && a[start] == b[start] { start += 1 }
    var endA = a.count
    var endB = b.count
    while endA > start && endB > start && a[endA - 1] == b[endB - 1] {
        endA -= 1
        endB -= 1
    }
    return (a[start..<endA], b[start..<endB])
}
