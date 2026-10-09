import Foundation

/// The SF Symbols offered as goal icons, grouped for the picker, and the bridge from the emoji
/// icons of earlier versions.
public enum SymbolCatalog {
    public struct Group: Identifiable, Sendable {
        public var name: String
        public var symbols: [String]
        public var id: String { name }

        public init(name: String, symbols: [String]) {
            self.name = name
            self.symbols = symbols
        }
    }

    public static let groups: [Group] = [
        Group(name: "Work", symbols: [
            "laptopcomputer", "desktopcomputer", "keyboard", "briefcase.fill", "folder.fill", "doc.text.fill",
            "chart.line.uptrend.xyaxis", "chart.bar.fill", "terminal.fill", "hammer.fill", "wrench.and.screwdriver.fill",
            "lightbulb.fill", "envelope.fill", "calendar", "checklist", "target", "flag.checkered", "paperplane.fill",
        ]),
        Group(name: "Learning", symbols: [
            "book.fill", "books.vertical.fill", "book.pages.fill", "graduationcap.fill", "character.book.closed.fill",
            "character.bubble.fill", "globe.americas.fill", "brain.head.profile", "brain.fill", "pencil.and.scribble",
            "square.and.pencil", "text.book.closed.fill", "magazine.fill", "newspaper.fill", "puzzlepiece.fill",
            "function", "atom", "flask.fill",
        ]),
        Group(name: "Health", symbols: [
            "heart.fill", "drop.fill", "pills.fill", "cross.case.fill", "bed.double.fill", "moon.zzz.fill",
            "lungs.fill", "carrot.fill", "fork.knife", "cup.and.saucer.fill", "mug.fill", "waterbottle.fill",
            "bandage.fill", "stethoscope", "allergens", "leaf.fill", "sun.max.fill", "eye.fill",
        ]),
        Group(name: "Fitness", symbols: [
            "figure.run", "figure.walk", "figure.outdoor.cycle", "figure.pool.swim", "figure.strengthtraining.traditional",
            "dumbbell.fill", "figure.yoga", "figure.hiking", "figure.climbing", "figure.dance", "figure.boxing",
            "figure.tennis", "figure.soccer", "figure.basketball", "sportscourt.fill", "bicycle", "flame.fill", "stopwatch.fill",
        ]),
        Group(name: "Mind", symbols: [
            "figure.mind.and.body", "sparkles", "sun.horizon.fill", "wind", "cloud.sun.fill", "moon.stars.fill",
            "heart.text.square.fill", "face.smiling.inverse", "hands.sparkles.fill", "leaf.circle.fill", "tree.fill",
            "water.waves", "bubbles.and.sparkles.fill", "hourglass", "timer", "bell.fill", "quote.bubble.fill", "infinity",
        ]),
        Group(name: "Creative", symbols: [
            "paintpalette.fill", "paintbrush.pointed.fill", "pencil.tip", "camera.fill", "photo.fill", "film.fill",
            "music.note", "guitars.fill", "pianokeys", "music.mic", "headphones", "theatermasks.fill",
            "scissors", "wand.and.stars", "cube.fill", "gamecontroller.fill", "pencil.and.outline", "text.quote",
        ]),
        Group(name: "Life", symbols: [
            "house.fill", "cart.fill", "dollarsign.circle.fill", "creditcard.fill", "banknote.fill", "chart.pie.fill",
            "person.2.fill", "figure.2.and.child.holdinghands", "phone.fill", "bubble.left.and.bubble.right.fill",
            "gift.fill", "pawprint.fill", "car.fill", "airplane", "suitcase.fill", "map.fill", "frying.pan.fill", "washer.fill",
        ]),
    ]

    public static let all: [String] = groups.flatMap(\.symbols)

    /// The default icon for a kind of goal.
    public static func defaultSymbol(for kind: GoalKind) -> String {
        switch kind {
        case .time: "timer"
        case .count: "checkmark.circle.fill"
        case .amount: "chart.bar.fill"
        case .milestones: "flag.checkered"
        case .books: "books.vertical.fill"
        }
    }

    /// The symbol closest to an emoji icon from an earlier version.
    public static func symbol(forEmoji emoji: String) -> String? {
        if let match = emojiSymbols[emoji] { return match }
        // Flags are pairs of regional indicators: almost always a language goal.
        if emoji.unicodeScalars.contains(where: { (0x1F1E6...0x1F1FF).contains($0.value) }) { return "character.bubble.fill" }
        // Ignore skin tones and variation selectors.
        let base = String(String.UnicodeScalarView(emoji.unicodeScalars.filter { !(0x1F3FB...0x1F3FF).contains($0.value) && $0.value != 0xFE0F && $0.value != 0x200D }))
        return emojiSymbols[base]
    }

    private static let emojiSymbols: [String: String] = [
        "🎯": "target", "💻": "laptopcomputer", "🧑‍💻": "laptopcomputer", "👨‍💻": "laptopcomputer", "👩‍💻": "laptopcomputer",
        "🖥": "desktopcomputer", "💼": "briefcase.fill", "📈": "chart.line.uptrend.xyaxis", "📊": "chart.bar.fill",
        "📝": "square.and.pencil", "✍": "pencil.and.scribble", "✏": "pencil.tip", "🚀": "paperplane.fill",
        "💡": "lightbulb.fill", "📧": "envelope.fill", "📅": "calendar", "✅": "checkmark.circle.fill", "🏁": "flag.checkered",
        "📚": "books.vertical.fill", "📖": "book.fill", "📕": "book.fill", "📗": "book.fill", "🎓": "graduationcap.fill",
        "🧠": "brain.head.profile", "🌍": "globe.americas.fill", "🌎": "globe.americas.fill", "🌏": "globe.americas.fill",
        "🗣": "character.bubble.fill", "🔬": "flask.fill", "🧪": "flask.fill", "🧩": "puzzlepiece.fill", "📰": "newspaper.fill",
        "❤": "heart.fill", "💧": "drop.fill", "🚰": "waterbottle.fill", "💊": "pills.fill", "😴": "bed.double.fill",
        "💤": "moon.zzz.fill", "🛌": "bed.double.fill", "🥕": "carrot.fill", "🥗": "fork.knife", "🍎": "carrot.fill",
        "☕": "cup.and.saucer.fill", "🍵": "mug.fill", "🫁": "lungs.fill", "🌞": "sun.max.fill", "☀": "sun.max.fill",
        "🏃": "figure.run", "🚶": "figure.walk", "🚴": "figure.outdoor.cycle", "🏊": "figure.pool.swim",
        "🏋": "figure.strengthtraining.traditional", "💪": "dumbbell.fill", "👟": "figure.run", "🥾": "figure.hiking",
        "🧗": "figure.climbing", "💃": "figure.dance", "🥊": "figure.boxing", "🎾": "figure.tennis", "⚽": "figure.soccer",
        "🏀": "figure.basketball", "🚲": "bicycle", "🔥": "flame.fill", "⏱": "stopwatch.fill", "⏲": "timer",
        "🧘": "figure.mind.and.body", "✨": "sparkles", "🌅": "sun.horizon.fill", "🌙": "moon.stars.fill", "🙏": "hands.sparkles.fill",
        "🌱": "leaf.fill", "🍃": "leaf.fill", "🌳": "tree.fill", "🌊": "water.waves", "⏳": "hourglass", "🔔": "bell.fill",
        "😊": "face.smiling.inverse", "🎨": "paintpalette.fill", "🖌": "paintbrush.pointed.fill", "📷": "camera.fill",
        "📸": "camera.fill", "🎬": "film.fill", "🎵": "music.note", "🎶": "music.note", "🎸": "guitars.fill", "🎹": "pianokeys",
        "🎤": "music.mic", "🎧": "headphones", "🎭": "theatermasks.fill", "🎮": "gamecontroller.fill", "🏠": "house.fill",
        "🛒": "cart.fill", "💰": "dollarsign.circle.fill", "💵": "banknote.fill", "💳": "creditcard.fill", "👥": "person.2.fill",
        "👨‍👩‍👧": "figure.2.and.child.holdinghands", "📞": "phone.fill", "💬": "bubble.left.and.bubble.right.fill", "🎁": "gift.fill",
        "🐶": "pawprint.fill", "🐱": "pawprint.fill", "🚗": "car.fill", "✈": "airplane", "🧳": "suitcase.fill", "🗺": "map.fill",
        "🍳": "frying.pan.fill", "🧺": "washer.fill", "🧹": "sparkles",
    ]
}
