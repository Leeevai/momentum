import Foundation

/// How dates are written to the data file and sync files.
///
/// Dates are stored as seconds since 1970, which round-trips exactly: what's read back is the
/// date that was written, to the last bit. ISO 8601 strings, used before 2.0, keep whole seconds,
/// so an in-memory value and its saved copy disagreed, and comparisons (undo matching a session,
/// a sync merge comparing records) depended on whether the file had been read back. Both forms
/// still decode. Exports stay readable, as ISO 8601 with milliseconds.
enum DateCoding {
    static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(date.formatted(fractionalISO8601))
            }
        } else {
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(date.timeIntervalSince1970)
            }
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: fractionalISO8601) {
                return date
            }
            if let date = try? Date(text, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a date: \(text)")
        }
        return decoder
    }

    private static let fractionalISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
