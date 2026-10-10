import Foundation
import Testing
@testable import MomentumCore

@Suite("Found to-dos")
struct FoundTodosTests {
    @Test("Instagram links lose their tracking query; other links keep what isn't tracking")
    func cleaningLinks() throws {
        let instagram = try #require(URL(string: "https://www.instagram.com/p/DeChTQDGH8O/?vrfl=MTFhOTQ5OWZhc3BrMA=="))
        let youtube = try #require(URL(string: "https://www.youtube.com/watch?v=zduSFxRajkE&si=abc&utm_source=ig"))
        let cleanInstagram = TodoText.cleanLink(instagram).absoluteString
        let cleanYouTube = TodoText.cleanLink(youtube).absoluteString
        #expect(cleanInstagram == "https://www.instagram.com/p/DeChTQDGH8O/")
        #expect(cleanYouTube == "https://www.youtube.com/watch?v=zduSFxRajkE")
    }

    @Test("A pasted link gets https when it has none, and text that isn't a link gives nothing")
    func pastedLinks() {
        let bare = TodoText.link(from: "  instagram.com/reel/ABC123/?igsh=xyz ")?.absoluteString
        let words = TodoText.link(from: "not a link at all")
        let empty = TodoText.link(from: "")
        #expect(bare == "https://instagram.com/reel/ABC123/")
        #expect(words == nil)
        #expect(empty == nil)
    }

    @Test("The first web link is picked out of a share sheet's message, without what wraps it")
    func linksInText() {
        let shared = TodoText.link(from: "Check out this reel by @coach https://www.instagram.com/reel/C9xYz/?igsh=MWQ1 so good")
        let lines = TodoText.link(from: "https://youtu.be/zduSFxRajkE?si=abc\nhttps://www.tiktok.com/@a/video/1")
        let wrapped = TodoText.link(from: "<https://www.youtube.com/watch?v=abc&feature=share>")
        let sentence = TodoText.link(from: "Saved from vm.tiktok.com/ZMabc123/.")
        let email = TodoText.link(from: "send it to me@example.com")
        let script = TodoText.link(from: "shortcuts://run-shortcut?name=x")
        #expect(shared?.absoluteString == "https://www.instagram.com/reel/C9xYz/")
        #expect(lines?.absoluteString == "https://youtu.be/zduSFxRajkE")
        #expect(wrapped?.absoluteString == "https://www.youtube.com/watch?v=abc")
        #expect(sentence?.absoluteString == "https://vm.tiktok.com/ZMabc123/")
        #expect(email == nil)
        #expect(script == nil)
    }

    @Test("Each site's tracking comes off its links; a look-alike site keeps its query")
    func cleaningSites() throws {
        let cases: [(String, String)] = [
            ("https://m.youtube.com/watch?v=abc&pp=ygUE&t=42", "https://m.youtube.com/watch?v=abc&t=42"),
            ("https://www.youtube.com/shorts/abc?feature=share", "https://www.youtube.com/shorts/abc"),
            ("https://x.com/name/status/123?s=46&t=aBc", "https://x.com/name/status/123"),
            ("https://www.threads.net/@name/post/C1?xmt=AQ", "https://www.threads.net/@name/post/C1"),
            ("https://instagr.am/p/C1/?igsh=x", "https://instagr.am/p/C1/"),
            ("https://notinstagram.com/p/1?page=2", "https://notinstagram.com/p/1?page=2"),
            ("https://example.com/recipe?feature=pasta&utm_source=ig", "https://example.com/recipe?feature=pasta"),
        ]
        for (pasted, expected) in cases {
            let url = try #require(URL(string: pasted))
            let cleaned = TodoText.cleanLink(url).absoluteString
            #expect(cleaned == expected, "\(pasted)")
        }
    }

    @Test("A goal's link is called by its site")
    func linkTitles() throws {
        let cases: [(String, String)] = [
            ("https://www.instagram.com/reel/a/", "Instagram"),
            ("https://instagr.am/p/a/", "Instagram"),
            ("https://vm.tiktok.com/ZMa/", "TikTok"),
            ("https://youtu.be/a", "YouTube"),
            ("https://music.youtube.com/watch?v=a", "YouTube"),
            ("https://www.awww.com/a", "awww.com"),
            ("https://example.org", "example.org"),
        ]
        for (link, expected) in cases {
            let url = try #require(URL(string: link))
            let title = TodoText.linkTitle(for: url)
            #expect(title == expected, "\(link)")
        }
    }

    @Test("Durations are read from clocks and from words")
    func durations() {
        let cases: [(String, TimeInterval?)] = [
            ("Let's build the GPT Tokenizer · 2:13:35", 8015),
            ("RAG from scratch 14:32", 872),
            ("1h 20m", 4800),
            ("about 1 hr 20 min", 4800),
            ("45 min workout", 2700),
            ("90 minutes", 5400),
            ("2 hours", 7200),
            ("30s plank", 30),
            ("3 steps to a better morning", nil),
            ("no time here", nil),
        ]
        for (text, expected) in cases {
            let parsed = TodoText.duration(in: text)
            #expect(parsed == expected, "\(text)")
        }
    }

    @Test("Without the on-device model, a to-do is named after what's said, then what's shown, then the file")
    func fallbackTitles() {
        let spoken = TodoText.fallbackTitle(transcript: "In this video, we build a RAG system from scratch. It takes an hour.",
                                            screenText: "RAG", fileName: "clip.mov")
        let shown = TodoText.fallbackTitle(transcript: "", screenText: "Morning stretch routine\n5 minutes", fileName: "clip.mov")
        let named = TodoText.fallbackTitle(transcript: "", screenText: "", fileName: "leg_day-workout.mp4")
        let nothing = TodoText.fallbackTitle(transcript: "", screenText: "", fileName: "")
        #expect(spoken == "We build a RAG system from scratch")
        #expect(shown == "Morning stretch routine")
        #expect(named == "Leg day workout")
        #expect(nothing == "Watch the video")
    }

    @Test("Greetings, stacked openers, the phone's interface and made-up file names don't name a to-do")
    func fallbackTitlesSkipNoise() {
        let greeting = TodoText.fallbackTitle(transcript: "Hey guys! Welcome back to my channel. Today we're making a one-pan lemon pasta.",
                                              screenText: "", fileName: "a.mov")
        let stacked = TodoText.fallbackTitle(transcript: "So, in this video, we build a RAG system.", screenText: "", fileName: "a.mov")
        let japanese = TodoText.fallbackTitle(transcript: "こんにちは。今日はレモンパスタを作ります。", screenText: "", fileName: "a.mov")
        let screen = TodoText.fallbackTitle(transcript: "", screenText: "9:41\n@coach.anna\nFollow\nOriginal audio\nMorning stretch routine",
                                            fileName: "a.mov")
        let camera = TodoText.fallbackTitle(transcript: "", screenText: "", fileName: "IMG_1234.MOV")
        let recording = TodoText.fallbackTitle(transcript: "", screenText: "", fileName: "RPReplay_Final1696.MP4")
        let random = TodoText.fallbackTitle(transcript: "", screenText: "", fileName: "8F3A1C2E-0F4B-4D0E-9B1F-2C3D4E5F6A7B.mov")
        #expect(greeting == "We're making a one-pan lemon pasta")
        #expect(stacked == "We build a RAG system")
        #expect(japanese == "今日はレモンパスタを作ります")
        #expect(screen == "Morning stretch routine")
        #expect(camera == "Watch the video")
        #expect(recording == "Watch the video")
        #expect(random == "Watch the video")
    }

    @Test("Lists are read from numbers, keycaps, steps and bullets; a decimal or a hyphenated number isn't an item")
    func listsWithoutModel() {
        let caption = """
            5 projects to build this weekend 🚀
            1️⃣ Build a tokenizer · 14:32
            2️⃣ Train a tiny GPT
            Step 3: Fine-tune it (20 min)
            #4 Ship a RAG app
            5 - Write it up
            ✅ Share what you made
            👉 Follow for more
            3.5 hours of practice
            10-minute ab workout
            """
        let items = TodoText.listItems(in: caption)
        let titles = items.map { $0.title }
        let durations = items.map { $0.duration }
        let expectedTitles = ["Build a tokenizer", "Train a tiny GPT", "Fine-tune it", "Ship a RAG app", "Write it up",
                              "Share what you made"]
        let expectedDurations: [TimeInterval?] = [872, nil, 1200, nil, nil, nil]
        #expect(titles == expectedTitles)
        #expect(durations == expectedDurations)
    }

    @Test("Without the model, several to-dos go in a goal named after the post's title in its caption")
    func goalNames() {
        let caption = """
            Save this for later 📌
            5 AI projects to build this weekend 🚀🔥 #ai @coach
            1. Build a tokenizer
            2. Train a tiny GPT
            """
        let todos = [FoundTodo(title: "Build a tokenizer", source: "Caption"), FoundTodo(title: "Train a tiny GPT", source: "Caption")]
        let fromCaption = TodoText.listName(for: todos, caption: caption)
        let onlyList = TodoText.listName(for: todos, caption: "1. Build a tokenizer\n2. Train a tiny GPT")
        let behindTags = TodoText.postTitle(in: "#fitness #workout\nhttps://instagram.com/p/x\nHow to learn SQL in 30 days:")
        let single = TodoText.listName(for: [todos[0]], caption: caption)
        #expect(fromCaption == "5 AI projects to build this weekend")
        #expect(onlyList == "Saved videos")
        #expect(behindTags == "How to learn SQL in 30 days")
        #expect(single == "Build a tokenizer")
    }

    @Test("A suggested goal name is tidied and kept short")
    func suggestedGoalNames() {
        let quoted = TodoText.goalName("“Rebuild AI projects.”")
        let long = TodoText.goalName("Morning mobility routine for runners who sit all day")
        #expect(quoted == "Rebuild AI projects")
        #expect(long == "Morning mobility routine for runners who")
    }

    @Test("A to-do's length is said in words, not as a time of day")
    func spokenDurations() {
        let english = Locale(identifier: "en_US")
        let short = Formatting.spokenDuration(872, locale: english)
        let long = Formatting.spokenDuration(3729, locale: english)
        #expect(short.contains("14 minutes") && short.contains("32 seconds"))
        #expect(long.contains("1 hour") && long.contains("2 minutes") && long.contains("9 seconds"))
        #expect(!short.contains(":"))
    }

    @Test("Titles read as to-dos: shouted captions in sentence case, without quotes or a full stop")
    func tidyingTitles() {
        let shouted = TodoText.tidyTitle("10 MIN AB WORKOUT")
        let quoted = TodoText.tidyTitle("“Build a RAG system.”")
        let kept = TodoText.tidyTitle("build GPT's tokenizer")
        let acronym = TodoText.tidyTitle("Learn SQL")
        #expect(shouted == "10 min ab workout")
        #expect(quoted == "Build a RAG system")
        #expect(kept == "Build GPT's tokenizer")
        #expect(acronym == "Learn SQL")
    }

    @Test("A duration at the end of a line comes off the title; one inside the name stays")
    func trailingDurations() {
        let clock = TodoText.removingTrailingDuration(from: "RAG from scratch · 14:32")
        let long = TodoText.removingTrailingDuration(from: "Self-driving car sim 2:11:04")
        let words = TodoText.removingTrailingDuration(from: "Morning stretch (5 min)")
        let named = TodoText.removingTrailingDuration(from: "10 min ab workout")
        let onlyTime = TodoText.removingTrailingDuration(from: "14:32")
        #expect(clock == "RAG from scratch")
        #expect(long == "Self-driving car sim")
        #expect(words == "Morning stretch")
        #expect(named == "10 min ab workout")
        #expect(onlyTime == "14:32")
    }

    @Test("To-dos become milestones of a new goal, with their durations and the post's link on the goal")
    func addingToNewGoal() throws {
        var data = AppData()
        let link = try #require(URL(string: "https://www.instagram.com/p/DeChTQDGH8O/"))
        let todos = [
            FoundTodo(title: "Build GPT's tokenizer", duration: 8015, link: link, source: "1.mp4"),
            FoundTodo(title: "  ", duration: 60, link: link, source: "2.mp4"),
            FoundTodo(title: "Build a RAG system", duration: .infinity, link: link, source: "3.mp4"),
        ]
        let newGoal = Goal(name: "Rebuild AI projects", kind: .milestones, target: 0)
        let id = data.addTodos(todos, to: nil, orNew: newGoal)
        let goal = try #require(data.goal(id))
        let titles = goal.milestones.map(\.title)
        let durations = goal.milestones.map(\.duration)
        let goalLinks = goal.links.map(\.url)
        #expect(id == newGoal.id)
        #expect(titles == ["Build GPT's tokenizer", "Build a RAG system"])
        #expect(durations == [8015, nil])
        #expect(goal.milestones.allSatisfy { $0.link == link })
        #expect(goalLinks == [link])
    }

    @Test("To-dos added to an existing goal follow its milestones, and its link isn't added twice")
    func addingToExistingGoal() throws {
        var data = AppData()
        let link = try #require(URL(string: "https://www.instagram.com/reel/ABC/"))
        var existing = Goal(name: "Workouts", kind: .milestones, target: 0)
        existing.milestones = [Milestone(title: "Warm up")]
        existing.links = [GoalLink(title: "Instagram", url: link)]
        data.upsert(existing)
        let id = data.addTodos([FoundTodo(title: "Leg day", duration: 600, link: link, source: "a.mov")],
                               to: existing.id, orNew: Goal(name: "Unused", kind: .milestones, target: 0))
        let goal = try #require(data.goal(id))
        let titles = goal.milestones.map(\.title)
        #expect(id == existing.id)
        #expect(data.goals.count == 1)
        #expect(titles == ["Warm up", "Leg day"])
        #expect(goal.links.count == 1)
    }

    @Test("A goal already has a to-do with its name, or the same video under another name")
    func existingMilestones() throws {
        let link = try #require(URL(string: "https://www.instagram.com/reel/ABC/"))
        var goal = Goal(name: "Workouts", kind: .milestones, target: 0)
        goal.milestones = [Milestone(title: "Leg  day", duration: 600, link: link)]
        let renamed = FoundTodo(title: "Do the leg workout", duration: 600.4, link: link, source: "a.mov")
        let sameName = FoundTodo(title: "leg day", source: "b.mov")
        let sameLink = FoundTodo(title: "Arm day", duration: 300, link: link, source: "c.mov")
        let has = [renamed, sameName, sameLink].map { goal.hasMilestone(like: $0) }
        #expect(has == [true, true, false])
    }

    @Test("Milestones from before durations and links decode, and the new fields survive a save")
    func milestoneDecoding() throws {
        let old = #"{"version": 2, "goals": [{"name": "G", "kind": "milestones", "target": 0, "milestones": [{"title": "Step"}]}]}"#
        let decoded = try #require(FileStore.decode(Data(old.utf8)).goals.first?.milestones.first)
        #expect(decoded.duration == nil)
        #expect(decoded.link == nil)

        var data = AppData()
        var goal = Goal(name: "G", kind: .milestones, target: 0)
        goal.milestones = [Milestone(title: "Watch", duration: 754, link: URL(string: "https://youtu.be/x"))]
        data.upsert(goal)
        let reloaded = try #require(FileStore.decode(JSONEncoder().encode(data)).goals.first?.milestones.first)
        #expect(reloaded.duration == 754)
        #expect(reloaded.link?.absoluteString == "https://youtu.be/x")
    }
}
