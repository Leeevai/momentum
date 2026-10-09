import Foundation

/// `momentum://` URLs: widgets and notifications use them to open the app on the right screen.
enum DeepLink: Equatable {
    case today
    case insights
    case goal(UUID)
    /// Opens one of a goal's links (widgets cannot open arbitrary URLs themselves).
    case openLink(goal: UUID, link: UUID)
    case newGoal

    static let scheme = "momentum"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today: components.host = "today"
        case .insights: components.host = "insights"
        case .goal(let id): components.host = "goal"; components.path = "/\(id.uuidString)"
        case .openLink(let goal, let link): components.host = "link"; components.path = "/\(goal.uuidString)/\(link.uuidString)"
        case .newGoal: components.host = "new"
        }
        return components.url ?? URL(string: "\(Self.scheme)://today")!
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }.compactMap(UUID.init(uuidString:))
        switch url.host() {
        case "today": self = .today
        case "insights": self = .insights
        case "new": self = .newGoal
        case "goal" where parts.count == 1: self = .goal(parts[0])
        case "link" where parts.count == 2: self = .openLink(goal: parts[0], link: parts[1])
        default: return nil
        }
    }
}
