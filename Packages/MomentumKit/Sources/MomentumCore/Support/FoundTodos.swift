import Foundation

/// A to-do found in something the user brought in (a saved video, a screenshot, a pasted caption):
/// what to do, how long it takes, and where it came from.
public struct FoundTodo: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    /// A video's length, or a duration written in the text, in seconds.
    public var duration: TimeInterval?
    public var link: URL?
    /// What it was found in, for the list it's shown in: a file name, or "Caption".
    public var source: String

    public init(id: UUID = UUID(), title: String, duration: TimeInterval? = nil, link: URL? = nil, source: String) {
        self.id = id
        self.title = title
        self.duration = duration
        self.link = link
        self.source = source
    }
}

extension AppData {
    /// Adds found to-dos as milestones, each with its duration and link, to the goal `goalID`, or
    /// else to `newGoal`, which is added first. A link every to-do shares (the post they came from)
    /// is also kept on the goal. Returns the goal's id.
    @discardableResult
    public mutating func addTodos(_ todos: [FoundTodo], to goalID: UUID?, orNew newGoal: Goal) -> UUID {
        let milestones = todos.compactMap { todo -> Milestone? in
            let title = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let duration = todo.duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            return Milestone(title: title, duration: duration, link: todo.link)
        }
        let links = Set(todos.compactMap(\.link))
        let shared = links.count == 1 && todos.allSatisfy({ $0.link != nil }) ? links.first : nil
        let id = goalID.flatMap { goal($0) }?.id ?? newGoal.id
        if goal(id) == nil {
            upsert(newGoal)
        }
        updateGoal(id) { goal in
            goal.milestones.append(contentsOf: milestones)
            if let shared, !goal.links.contains(where: { $0.url == shared }) {
                goal.links.append(GoalLink(title: TodoText.linkTitle(for: shared), url: shared))
            }
        }
        return id
    }
}

/// The text handling behind found to-dos: cleaning links, reading durations, and naming a to-do
/// when the on-device model can't.
public enum TodoText {
    /// Query items that only track who shared a link and where it was opened.
    private static let trackingItems: Set<String> = ["igsh", "igshid", "vrfl", "fbclid", "gclid", "si", "mibextid"]

    /// `url` without its tracking query items. Instagram and TikTok post links need no query at all.
    public static func cleanLink(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let host = components.host?.lowercased() ?? ""
        if host.hasSuffix("instagram.com") || host.hasSuffix("tiktok.com") {
            components.queryItems = nil
        } else if let items = components.queryItems {
            let kept = items.filter { !trackingItems.contains($0.name.lowercased()) && !$0.name.lowercased().hasPrefix("utm_") }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components.url ?? url
    }

    /// A link typed or pasted by hand: trimmed, given https when it has no scheme, and cleaned.
    public static func link(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return cleanLink(url)
    }

    /// What to call a link on a goal: the site it's on.
    public static func linkTitle(for url: URL) -> String {
        let host = (url.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        switch host {
        case let host where host.hasSuffix("instagram.com"): return "Instagram"
        case let host where host.hasSuffix("tiktok.com"): return "TikTok"
        case "youtube.com", "m.youtube.com", "youtu.be": return "YouTube"
        default: return host.isEmpty ? "Link" : host
        }
    }

    /// A duration written as text: "2:13:35", "14:32", "1h 20m", "1 hr 20 min", "45 min",
    /// "90 minutes", "2 hours" or "30s". Nil when there's none.
    public static func duration(in text: String) -> TimeInterval? {
        let lowered = text.lowercased()
        if let match = lowered.firstMatch(of: #/(\d{1,2}):([0-5]\d):([0-5]\d)/#) {
            return Double(match.1)! * 3600 + Double(match.2)! * 60 + Double(match.3)!
        }
        if let match = lowered.firstMatch(of: #/(\d{1,3}):([0-5]\d)/#) {
            return Double(match.1)! * 60 + Double(match.2)!
        }
        var total: TimeInterval = 0
        for match in lowered.matches(of: #/(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b/#) {
            guard let value = Double(match.1) else { continue }
            switch match.2.first {
            case "h": total += value * 3600
            case "m": total += value * 60
            default: total += value
            }
        }
        return total > 0 ? total : nil
    }

    /// A to-do's name as it should read: trimmed of quotes and a closing full stop, text shouted in
    /// capitals (as on-screen captions are) put in sentence case, and the first letter capitalized.
    public static func tidyTitle(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’")))
        while text.hasSuffix(".") { text.removeLast() }
        let letters = text.filter(\.isLetter)
        if letters.count > 3, letters.allSatisfy(\.isUppercase) {
            text = text.lowercased()
        }
        guard let first = text.first else { return "" }
        return first.uppercased() + text.dropFirst()
    }

    /// `title` without a duration written at its end ("RAG from scratch · 14:32" is "RAG from
    /// scratch"). A duration elsewhere is part of the name ("10 min ab workout") and stays.
    public static func removingTrailingDuration(from title: String) -> String {
        let clock = #/[\s·•|,(\[-]*\b\d{1,2}(?::[0-5]\d){1,2}[)\]]?\s*$/#
        let words = #/[\s·•|,(\[-]*\b\d+(?:\.\d+)?\s*(?:hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b[)\]]?\s*$/#
        let stripped = title.replacing(clock, with: "").replacing(words, with: "")
        return stripped.isEmpty ? title : stripped
    }

    /// Openers that say nothing about the task.
    private static let openers = ["in this video,", "in this video", "in today's video,", "hey guys,", "hey everyone,",
                                  "hi everyone,", "so,", "okay,", "ok,", "today,"]

    /// A to-do's name when the on-device model isn't available: the first sentence of what's said,
    /// else the first line on screen, else the file's name, shortened to `maxWords`.
    public static func fallbackTitle(transcript: String, screenText: String, fileName: String, maxWords: Int = 8) -> String {
        let sentence = transcript.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? ""
        var title = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        for opener in openers where title.lowercased().hasPrefix(opener) {
            title = String(title.dropFirst(opener.count)).trimmingCharacters(in: .whitespaces)
        }
        if title.isEmpty {
            title = screenText.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        if title.isEmpty {
            title = (fileName as NSString).deletingPathExtension
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
        }
        let words = title.split(separator: " ")
        title = tidyTitle(words.prefix(maxWords).joined(separator: " "))
        return title.isEmpty ? "Watch the video" : title
    }
}
