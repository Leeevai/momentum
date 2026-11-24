import Foundation

/// What a goal can follow while it works through it, one at a time: the book being read, a course,
/// a series, or a video. Whatever it is, it's kept in the goal's `books` as a `Book` record, whose
/// `currentPage` and `totalPages` hold the position and the length in the goal's own unit: pages,
/// lessons, episodes, or seconds for a video on a time goal. Moving the position logs the
/// difference on the goal, and logging an amount moves the position (`AppData.logReading`).
///
/// It comes from what the goal measures (`Goal.follows`), so it's never stored: an older version
/// sees a course goal as a plain amount goal, logs plain amounts, and leaves the position alone.
public enum FollowKind: String, CaseIterable, Identifiable, Sendable {
    /// A book, on a books goal or an amount goal counted in pages.
    case book
    /// A course, on a goal counted in lessons, modules, classes or lectures.
    case course
    /// A series or a playlist, on a goal counted in episodes or videos.
    case series
    /// A video of known length, on a time goal: "watched up to 1:23:40".
    case video

    public var id: String { rawValue }

    /// "Book", "Course", "Series", "Video".
    public var title: String {
        switch self {
        case .book: "Book"
        case .course: "Course"
        case .series: "Series"
        case .video: "Video"
        }
    }

    /// "book", "course", "series", "video".
    public var noun: String { title.lowercased() }

    /// "books", "courses", "series", "videos".
    public var pluralNoun: String { self == .series ? noun : noun + "s" }

    /// The heading of its card on the goal screen.
    public var sectionTitle: String {
        switch self {
        case .book: "Reading"
        case .course: "Course"
        case .series, .video: "Watching"
        }
    }

    public var symbolName: String {
        switch self {
        case .book: "book"
        case .course: "graduationcap"
        case .series: "tv"
        case .video: "play.rectangle"
        }
    }

    /// Whether the position is a time into it, in seconds, rather than a count of parts.
    public var isTimed: Bool { self == .video }
}

extension Goal {
    /// The units that make a goal follow something, with the part they count, singular and plural.
    private static let followedUnits: [String: (kind: FollowKind, one: String, many: String)] = {
        var units: [String: (kind: FollowKind, one: String, many: String)] = [:]
        func add(_ kind: FollowKind, _ one: String, _ many: String, also aliases: [String] = []) {
            for unit in [one, many] + aliases { units[unit] = (kind, one, many) }
        }
        add(.book, "page", "pages", also: ["pg", "pgs"])
        add(.course, "lesson", "lessons")
        add(.course, "module", "modules")
        add(.course, "class", "classes")
        add(.course, "lecture", "lectures")
        add(.series, "episode", "episodes", also: ["ep", "eps"])
        add(.series, "video", "videos")
        return units
    }()

    private var followedUnit: (kind: FollowKind, one: String, many: String)? {
        Self.followedUnits[unit.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// What the goal follows, from what it measures: a book on a books goal or an amount goal in
    /// pages, a course on a count or amount goal in lessons (or modules, classes, lectures), a
    /// series on one in episodes or videos, and a video on a time goal. Nil for anything else.
    /// A time goal only shows it once a video has been added.
    public var follows: FollowKind? {
        switch kind {
        case .books:
            return .book
        case .time:
            return .video
        case .milestones:
            return nil
        case .count, .amount:
            // Pages keep a place in a book only on an amount goal, as they always have.
            guard let match = followedUnit, match.kind != .book || kind == .amount else { return nil }
            return match.kind
        }
    }

    /// The part the position counts, singular and plural: ("page", "pages"), ("lesson", "lessons"),
    /// ("episode", "episodes"). Nil when the goal follows nothing, or a video, whose position is a time.
    public var followedParts: (one: String, many: String)? {
        switch follows {
        case .book:
            return (one: "page", many: "pages")
        case .course, .series:
            guard let match = followedUnit else { return nil }
            return (one: match.one, many: match.many)
        case .video, nil:
            return nil
        }
    }

    /// An amount of the parts the goal follows: "24 pages", "1 lesson", or "40m" into a video.
    public func formatParts(_ count: Double) -> String {
        guard let parts = followedParts else { return Formatting.duration(count) }
        return "\(Formatting.number(count)) \(abs(count - 1) < 0.0001 ? parts.one : parts.many)"
    }

    /// Where an item is up to: "Page 134 of 420", "Lesson 7 of 24", "Episode 5",
    /// "1:23:40 of 2:10:00".
    public func positionText(of item: Book) -> String {
        let total = item.totalPages.flatMap { $0 > 0 ? $0 : nil }
        if follows == .video {
            let reached = Formatting.clock(Double(item.currentPage))
            return total.map { "\(reached) of \(Formatting.clock(Double($0)))" } ?? reached
        }
        let part = followedParts?.one ?? "page"
        let name = part.prefix(1).uppercased() + part.dropFirst()
        return total.map { "\(name) \(item.currentPage) of \($0)" } ?? "\(name) \(item.currentPage)"
    }

    /// What's left of an item: "286 pages left", "1 lesson left", "46:20 left". Nil without a length.
    public func remainingText(of item: Book) -> String? {
        guard let total = item.totalPages, total > 0 else { return nil }
        let left = max(0, total - item.currentPage)
        if follows == .video { return "\(Formatting.clock(Double(left))) left" }
        return "\(formatParts(Double(left))) left"
    }
}
