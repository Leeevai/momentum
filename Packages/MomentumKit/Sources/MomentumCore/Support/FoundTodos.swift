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
    /// Sites whose post links need no query at all: all it says is who shared the post, and where.
    private static let queryFreeSites = ["instagram.com", "instagr.am", "tiktok.com", "x.com", "twitter.com", "threads.net"]
    private static let youTubeSites = ["youtube.com", "youtu.be"]
    /// Query items that only track who shared a link and where it was opened.
    private static let trackingItems: Set<String> = ["igsh", "igshid", "vrfl", "fbclid", "gclid", "si", "mibextid"]
    /// YouTube's own: what was tapped to share the video, and the search it was found by.
    private static let youTubeTrackingItems: Set<String> = ["feature", "pp"]

    /// `url` without its tracking query items. Instagram, TikTok, X and Threads post links need no
    /// query at all.
    public static func cleanLink(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let host = components.host?.lowercased() ?? ""
        if queryFreeSites.contains(where: { isOn(host, $0) }) {
            components.queryItems = nil
        } else if let items = components.queryItems {
            let isYouTube = youTubeSites.contains { isOn(host, $0) }
            let kept = items.filter { item in
                let name = item.name.lowercased()
                return !trackingItems.contains(name) && !name.hasPrefix("utm_")
                    && !(isYouTube && youTubeTrackingItems.contains(name))
            }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components.url ?? url
    }

    /// The post's link in text typed or pasted by hand, which is often a share sheet's whole message
    /// ("Watch this reel by @name https://…"): the first web link in it, given https when it was
    /// written without a scheme, and cleaned. Nil when there's no web link.
    public static func link(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: whole) {
            // Only web pages: not an email address (mailto:), nor a link that would open another app.
            guard let scheme = match.url?.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  let range = Range(match.range, in: text) else { continue }
            // Written without a scheme, a link is detected as http; posts are on https.
            let found = String(text[range])
            let hasScheme = found.lowercased().hasPrefix("http://") || found.lowercased().hasPrefix("https://")
            guard let url = URL(string: hasScheme ? found : "https://" + found), url.host != nil else { continue }
            return cleanLink(url)
        }
        return nil
    }

    /// What to call a link on a goal: the site it's on.
    public static func linkTitle(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        if isOn(host, "instagram.com") || isOn(host, "instagr.am") { return "Instagram" }
        if isOn(host, "tiktok.com") { return "TikTok" }
        if youTubeSites.contains(where: { isOn(host, $0) }) { return "YouTube" }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return site.isEmpty ? "Link" : site
    }

    /// Whether `host` is `site` or one of its subdomains: "www.instagram.com" is on "instagram.com",
    /// "notinstagram.com" isn't.
    private static func isOn(_ host: String, _ site: String) -> Bool {
        host == site || host.hasSuffix("." + site)
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

    /// Openers that say nothing about the task, stripped from the start of a spoken sentence however
    /// they're stacked: "So, in this video, we build…".
    private static let openers = ["in this video", "in today's video", "in this reel", "hey guys", "hey everyone",
                                  "hey there", "hi guys", "hi everyone", "hi there", "hello everyone", "hello", "hey",
                                  "hi", "so", "okay", "ok", "alright", "all right", "today", "now", "well"]

    /// Spoken sentences that greet or ask for something, and never say what to do.
    private static let greetings = ["welcome back", "welcome to", "what's up", "whats up", "like and subscribe",
                                    "subscribe", "don't forget to", "make sure to like", "make sure to subscribe",
                                    "follow me", "follow for more", "comment below"]

    /// List items that ask for something rather than say what to do.
    private static let requests = ["follow for more", "follow me", "like and", "like this", "comment", "save this",
                                   "save for later", "subscribe", "tag a", "tag someone", "tag your", "link in bio",
                                   "dm me", "share this", "share with"]

    /// Text a screen recording picks up from the phone or the app rather than the video.
    private static let interfaceText: Set<String> = ["follow", "following", "like", "likes", "share", "send", "reply",
                                                     "comment", "comments", "more", "reels", "for you", "explore",
                                                     "sponsored", "subscribe", "subscribed", "verified", "live",
                                                     "home", "search", "save", "saved", "remix", "use template"]

    /// Words a camera, a screen recording or an app names files with, which say nothing about them.
    private static let fileNameWords: Set<String> = ["img", "vid", "mov", "pxl", "dsc", "dscn", "mvi", "gopr", "trim",
                                                     "rpreplay", "final", "screenrecording", "screen", "recording",
                                                     "at", "copy", "video", "image", "photo", "fullsizerender"]

    /// A to-do's name when the on-device model isn't available: the first spoken sentence that says
    /// something (not a greeting, at least three words), else the first line on screen that isn't the
    /// phone's or the app's, else the file's name unless a camera or an app made it up, shortened to
    /// `maxWords`; else "Watch the video".
    public static func fallbackTitle(transcript: String, screenText: String, fileName: String, maxWords: Int = 8) -> String {
        let sentences = transcript.split(whereSeparator: { ".!?\n。！？".contains($0) })
        var title = sentences.lazy.map { withoutOpeners(String($0)) }.first(where: isTask) ?? ""
        if title.isEmpty {
            let lines = screenText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            title = lines.first { !isInterface($0) } ?? ""
        }
        if title.isEmpty {
            let stem = (fileName as NSString).deletingPathExtension
            if !isMadeUp(stem) {
                title = stem.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            }
        }
        let words = title.split(separator: " ")
        title = tidyTitle(words.count > 1 ? words.prefix(maxWords).joined(separator: " ") : String(title.prefix(40)))
        return title.isEmpty ? "Watch the video" : title
    }

    /// The to-dos a screenshot or a caption lists, read without the on-device model: each line that
    /// starts like a list item, numbered ("1.", "1)", "1 -", "1/", "#1", "Step 1:", "1️⃣") or bulleted
    /// ("-", "•", "✅", "👉" and the like), with a duration written beside it. Items that only ask to
    /// follow, like, comment or share are left out.
    public static func listItems(in text: String) -> [(title: String, duration: TimeInterval?)] {
        text.split(whereSeparator: \.isNewline).compactMap { line -> (title: String, duration: TimeInterval?)? in
            guard let item = listItem(String(line)) else { return nil }
            let title = tidyTitle(removingTrailingDuration(from: item))
            guard !title.isEmpty, !requests.contains(where: { startsWithWord($0, title) }) else { return nil }
            return (title, duration(in: item))
        }
    }

    /// What follows a line's list marker; nil when the line doesn't start like a list item. A number
    /// followed by more digits ("3.5 hours", "10:30") or by a hyphenated word ("10-minute") isn't one.
    static func listItem(_ line: String) -> String? {
        // Keycap numbers (1️⃣) read as "1)", and emoji bullets without their variation selector.
        let plain = line.replacingOccurrences(of: "\u{FE0F}", with: "")
            .replacingOccurrences(of: "\u{20E3}", with: ")")
            .replacingOccurrences(of: "🔟", with: "10)")
        let numbered = #/^\s*(?:step\s*)?\d{1,2}\s*(?:[.):](?!\d)|\s[-–—]\s|/(?!\d))\s*(.+)$/#.ignoresCase()
        let hashed = #/^\s*#\d{1,2}[.):]?\s+(.+)$/#
        let bulleted = #/^\s*[-–—•*▪◾▫●○◦‣⁃✓✔✅☑👉➡▶►→🔹🔸⭐📌]+\s*(.+)$/#
        if let match = plain.firstMatch(of: numbered) { return String(match.1) }
        if let match = plain.firstMatch(of: hashed) { return String(match.1) }
        if let match = plain.firstMatch(of: bulleted) { return String(match.1) }
        return nil
    }

    /// `sentence` without the openers it starts with, however many: "So, in this video, we build" is
    /// "we build".
    private static func withoutOpeners(_ sentence: String) -> String {
        var text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        while let opener = openers.first(where: { startsWithWord($0, text) }) {
            text = String(text.dropFirst(opener.count))
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",:;!-–—")))
        }
        return text
    }

    /// Whether a spoken sentence says what to do: a few words that aren't a greeting or a request.
    /// Chinese and Japanese, written without spaces, need a few more characters than a greeting has.
    private static func isTask(_ sentence: String) -> Bool {
        let words = sentence.split(separator: " ")
        let spaceless = words.count == 1 && sentence.count >= 6
            && sentence.unicodeScalars.contains { $0.properties.isIdeographic || (0x3040...0x30FF).contains($0.value) }
        return (words.count >= 3 || spaceless) && !greetings.contains { startsWithWord($0, sentence) }
    }

    /// Whether `text` starts with `phrase` as whole words, ignoring case: "so" starts "So, we", not
    /// "Some" or "So's".
    private static func startsWithWord(_ phrase: String, _ text: String) -> Bool {
        guard text.lowercased().hasPrefix(phrase) else { return false }
        guard let next = text.dropFirst(phrase.count).first else { return true }
        return next.isWhitespace || ",:;!-–—".contains(next)
    }

    /// Whether a line on screen is the phone's or the app's: the clock or a count ("9:41", "1.2K"),
    /// a handle or a hashtag, or a button.
    private static func isInterface(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return line.filter(\.isLetter).count < 3 || line.hasPrefix("@") || line.hasPrefix("#")
            || interfaceText.contains(lowered) || lowered.hasPrefix("liked by") || lowered.hasPrefix("original audio")
            || lowered.hasPrefix("view all")
    }

    /// Whether a file's name was made up by a camera, a screen recording or an app ("IMG_1234",
    /// "RPReplay_Final1696", a UUID) rather than given by someone.
    private static func isMadeUp(_ stem: String) -> Bool {
        if UUID(uuidString: stem) != nil { return true }
        let words = stem.lowercased().split(whereSeparator: { !$0.isLetter })
        return words.allSatisfy { fileNameWords.contains(String($0)) }
    }
}
