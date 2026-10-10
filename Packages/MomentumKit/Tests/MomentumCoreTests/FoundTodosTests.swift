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
