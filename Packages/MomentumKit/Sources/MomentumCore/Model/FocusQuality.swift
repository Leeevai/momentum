import Foundation

/// How a focus session went, rated with one tap after it ends.
public enum FocusQuality: Int, Codable, CaseIterable, Identifiable, Comparable, Sendable {
    case scattered = 1
    case steady
    case flow

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .scattered: "Scattered"
        case .steady: "Steady"
        case .flow: "In the flow"
        }
    }

    public var detail: String {
        switch self {
        case .scattered: "Hard to stay on it"
        case .steady: "Kept at it"
        case .flow: "Lost track of time"
        }
    }

    public var symbolName: String {
        switch self {
        case .scattered: "wind"
        case .steady: "metronome.fill"
        case .flow: "water.waves"
        }
    }

    public static func < (lhs: FocusQuality, rhs: FocusQuality) -> Bool { lhs.rawValue < rhs.rawValue }
}
