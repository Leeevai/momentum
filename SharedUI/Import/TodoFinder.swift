import AVFoundation
import Foundation
import ImageIO
import MomentumCore
import UniformTypeIdentifiers
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Speech)
import Speech
#endif

/// Finds to-dos in what the user brings in, entirely on the device: a video's length, what's said
/// in it (on-device speech recognition, macOS 26 and iOS 26), the text on screen (Vision), and the
/// to-do's name from Apple's on-device language model where the system has one. Without the model,
/// a to-do is named from the text itself. Nothing is sent anywhere.
enum TodoFinder {
    /// How far the search has got: what it's doing, and how much of the whole is done, from 0 to 1.
    struct Progress: Equatable {
        var message: String
        var fraction: Double
    }

    /// Something the search couldn't do, and the files it happened with.
    struct Problem: Identifiable, Equatable {
        var reason: String
        var files: [String]

        var id: String { reason }
    }

    /// What the search found, and what it couldn't do along the way.
    struct Findings {
        var todos: [FoundTodo] = []
        var problems: [Problem] = []

        /// Notes `reason` for `file`, under the same reason as other files it happened with.
        mutating func note(_ reason: String, for file: String) {
            if let index = problems.firstIndex(where: { $0.reason == reason }) {
                problems[index].files.append(file)
            } else {
                problems.append(Problem(reason: reason, files: [file]))
            }
        }
    }

    /// What a file holds, before it's turned into to-dos, and what couldn't be read of it.
    struct Material {
        var name: String
        var isVideo: Bool
        var duration: TimeInterval?
        var transcript = ""
        var screenText = ""
        var problem: String?
    }

    /// Reports one file's progress as a share of the whole search.
    private struct Reporter {
        let index: Int
        let count: Int
        let progress: @MainActor (Progress) -> Void

        /// `message`, with the file's place in the batch, and `done` of the file, from 0 to 1.
        func callAsFunction(_ message: String, _ done: Double) async {
            let counter = count > 1 ? " (\(index + 1) of \(count))" : ""
            let fraction = (Double(index) + min(max(done, 0), 1)) / Double(count)
            await progress(Progress(message: message + counter, fraction: fraction))
        }
    }

    /// Whether the on-device model names the to-dos here, and if not, why.
    static var modelNote: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings to have the to-dos named by on-device AI. Until then they're named from what the video says."
            case .unavailable(.modelNotReady):
                return "Apple's on-device model is still downloading; until it's ready, to-dos are named from what the video says."
            case .unavailable:
                return "This device can't run Apple's on-device model, so to-dos are named from what the video says."
            }
        }
        #endif
        return "On-device AI needs macOS 26 or iOS 26; until then, to-dos are named from the text in the video."
    }

    /// The to-dos in `files` (videos, audio and screenshots) and in `caption`: one per video, as long
    /// as the video; any number per screenshot or caption. Each carries `link`. Stops early, with
    /// what it found so far, when its task is cancelled.
    static func todos(in files: [URL], caption: String, link: URL?,
                      progress: @escaping @MainActor (Progress) -> Void) async -> Findings {
        var findings = Findings()
        let note = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        // A caption on its own, or with screenshots, lists to-dos of its own (a post's numbered list).
        let readsCaption = !note.isEmpty && !files.contains(where: isVideo)
        let steps = files.count + (readsCaption ? 1 : 0)
        for (index, file) in files.enumerated() {
            if Task.isCancelled { return findings }
            let report = Reporter(index: index, count: steps, progress: progress)
            let name = file.lastPathComponent
            let material = await self.material(of: file, report: report)
            if Task.isCancelled { return findings }
            if let problem = material.problem { findings.note(problem, for: name) }
            await report("Naming the to-dos in \(name)…", 0.9)
            if material.isVideo {
                let (title, named) = await videoTitle(for: material, caption: note)
                if !named { findings.note("Apple's on-device model couldn't name it; rename it if the name is off.", for: name) }
                findings.todos.append(FoundTodo(title: title, duration: material.duration, link: link, source: name))
            } else {
                let items = await listedTodos(in: material.screenText, caption: "")
                if items.isEmpty, material.problem == nil { findings.note("No list of to-dos was found in it.", for: name) }
                findings.todos += items.map { FoundTodo(title: $0.title, duration: $0.duration, link: link, source: name) }
            }
        }
        if readsCaption, !Task.isCancelled {
            await Reporter(index: files.count, count: steps, progress: progress)("Reading the caption…", 0)
            let items = await listedTodos(in: note, caption: "")
            findings.todos += items.map { FoundTodo(title: $0.title, duration: $0.duration, link: link, source: "Caption") }
        }
        return findings
    }

    /// A name for the list the to-dos go in.
    static func listName(for todos: [FoundTodo], caption: String) async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *), SystemLanguageModel.default.isAvailable, todos.count > 1 {
            let prompt = """
            To-dos: \(todos.map(\.title).joined(separator: "; "))
            Caption: \(String(caption.prefix(600)))
            """
            if let answer = try? await LanguageModelSession(instructions: Self.listInstructions)
                .respond(to: prompt, generating: ListName.self) {
                let name = answer.content.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
        }
        #endif
        return todos.count == 1 ? todos[0].title : "Saved videos"
    }

    // MARK: - Reading files

    private static func isVideo(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .audiovisualContent) ?? false
    }

    /// Reads a file, reporting each step as a share of it: measuring a video, listening to it (most
    /// of the time), reading its frames, then naming, from 0.9.
    private static func material(of url: URL, report: Reporter) async -> Material {
        let name = url.lastPathComponent
        guard isVideo(url) else {
            await report("Reading \(name)…", 0)
            guard let text = imageText(at: url) else {
                return Material(name: name, isVideo: false, problem: "It couldn't be opened as an image.")
            }
            return Material(name: name, isVideo: false, screenText: text)
        }
        await report("Measuring \(name)…", 0)
        let asset = AVURLAsset(url: url)
        let loaded = try? await asset.load(.duration, .isPlayable)
        guard let loaded, loaded.1 else {
            return Material(name: name, isVideo: true,
                            problem: "Momentum can't play it, so it has no length.")
        }
        let seconds = loaded.0.seconds
        var material = Material(name: name, isVideo: true, duration: seconds.isFinite && seconds > 0 ? seconds : nil)
        guard !Task.isCancelled else { return material }
        await report("Listening to \(name)…", 0.05)
        do {
            material.transcript = try await transcript(of: asset, duration: material.duration) { message, done in
                await report(message ?? "Listening to \(name)…", 0.05 + 0.7 * done)
            }
        } catch let problem as ListeningProblem {
            material.problem = problem.reason
        } catch {
            material.problem = ListeningProblem.failed.reason
        }
        guard !Task.isCancelled else { return material }
        await report("Reading \(name)…", 0.75)
        material.screenText = await frameText(of: asset, duration: material.duration ?? 0)
        return material
    }

    /// How much of a video's sound is transcribed. Naming reads the first 3,000 characters of what's
    /// said, a few minutes of speech, so a long talk isn't worth exporting and transcribing whole.
    private static let listeningSpan: TimeInterval = 5 * 60

    /// Why what's said in a video couldn't be used, as the review puts it.
    private enum ListeningProblem: Error {
        case unavailable, failed
        case download(language: String)

        var reason: String {
            switch self {
            case .unavailable: "This device can't recognize speech."
            case .failed: "Its speech couldn't be recognized."
            case .download(let language):
                "Speech recognition for \(language) couldn't be downloaded. Check the connection, then look again."
            }
        }
    }

    /// What's said in the file, on-device: empty when it has no sound, and before macOS 26 and iOS 26.
    /// `report` gets a message to show instead of the usual one, if any, and how much is done.
    private static func transcript(of asset: AVURLAsset, duration: TimeInterval?,
                                   report: @escaping (String?, Double) async -> Void) async throws -> String {
        #if canImport(Speech)
        if #available(macOS 26.0, iOS 26.0, *) {
            return try await speech(in: asset, duration: duration, report: report)
        }
        #endif
        return ""
    }

    #if canImport(Speech)
    @available(macOS 26.0, iOS 26.0, *)
    private static func speech(in asset: AVURLAsset, duration: TimeInterval?,
                               report: @escaping (String?, Double) async -> Void) async throws -> String {
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { return "" }
        guard SpeechTranscriber.isAvailable else { throw ListeningProblem.unavailable }
        // The analyzer reads audio files: the sound comes out of the video first.
        let audio = ImportScratch.newItem(named: "audio").appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at: audio) }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ListeningProblem.failed
        }
        if let duration, duration > listeningSpan {
            export.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: listeningSpan, preferredTimescale: 600))
        }
        try await export.export(to: audio, as: .m4a)
        try Task.checkCancellation()

        var locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        if locale == nil {
            locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        }
        guard let locale else { throw ListeningProblem.unavailable }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        // The system downloads the language's speech model the first time.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let language = locale.language.languageCode.flatMap { Locale.current.localizedString(forLanguageCode: $0.identifier) }
                ?? locale.identifier
            do {
                try await download(request) { done in
                    await report("Downloading speech recognition for \(language)… \(Int(done * 100))%", 0)
                }
            } catch {
                try Task.checkCancellation()
                throw ListeningProblem.download(language: language)
            }
        }
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: audio)
        // How much of the sound is heard so far moves the bar.
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        func listen() async throws -> String {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
                if seconds > 0 { await report(nil, min(result.range.end.seconds / seconds, 1)) }
            }
            return text
        }
        async let text = listen()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Finishing the analyzer ends the results, so the text above is always delivered, and
        // closing the sheet stops the analysis rather than letting it run to the end of the file.
        try await withTaskCancellationHandler {
            do {
                if let end = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
        return try await text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Downloads a speech model, reporting how much of it is in twice a second.
    @available(macOS 26.0, iOS 26.0, *)
    private static func download(_ request: AssetInstallationRequest,
                                 report: @escaping (Double) async -> Void) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await request.downloadAndInstall() }
            group.addTask {
                while true {
                    await report(request.progress.fractionCompleted)
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
            // The download finishes first: the watch on it only ends when cancelled.
            _ = try await group.next()
            group.cancelAll()
        }
    }
    #endif

    /// The text on screen across the video: a few frames read with Vision, each line once.
    private static func frameText(of asset: AVURLAsset, duration: TimeInterval) async -> String {
        guard (try? await asset.loadTracks(withMediaType: .video).isEmpty) == false else { return "" }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let moments = duration > 0 ? [0.1, 0.3, 0.5, 0.7, 0.9].map { $0 * duration } : [0]
        var lines: [String] = []
        for moment in moments where !Task.isCancelled {
            guard let frame = try? await generator.image(at: CMTime(seconds: moment, preferredTimescale: 600)).image else { continue }
            for line in recognizedText(in: frame) where !lines.contains(line) {
                lines.append(line)
            }
        }
        return lines.prefix(60).joined(separator: "\n")
    }

    /// The text in an image, read from a copy at most 3,000 pixels long and turned the right way up:
    /// a 48-megapixel photo is some 200 MB decoded, and text on its side isn't read. Nil when it
    /// can't be opened as an image.
    private static func imageText(at url: URL) -> String? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3000,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return recognizedText(in: image).joined(separator: "\n")
    }

    private static func recognizedText(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 1 }
    }

    // MARK: - Naming

    private static let videoInstructions = """
        You turn a saved social media video into one to-do for someone who wants to do what the video \
        shows or teaches. Answer with a short imperative to-do of 2 to 8 words, like "Do the 10-minute \
        ab workout", "Cook the one-pan lemon pasta" or "Build a RAG system", in sentence case. Use the \
        video's own names for things. Ignore requests to like, follow, comment or share.
        """

    private static let listInstructions = """
        You turn social media posts into to-do lists. List only the concrete things the viewer is told \
        to do, make, build, watch or practice, in the post's order, each as a short imperative to-do. \
        Leave out advice, opinions, and requests to like, follow, comment or share. When a duration is \
        written next to an item (like 14:32, 1:05:00 or 20 min), give it.
        """

    /// A video's to-do, and whether Apple's model named it as meant: false when the model is there
    /// but couldn't, and the name comes from the video's text instead.
    private static func videoTitle(for material: Material, caption: String) async -> (title: String, named: Bool) {
        let fallback = TodoText.fallbackTitle(transcript: material.transcript, screenText: material.screenText,
                                              fileName: material.name)
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let prompt = """
            Caption: \(String(caption.prefix(800)))
            Spoken: \(String(material.transcript.prefix(3000)))
            On screen: \(String(material.screenText.prefix(1000)))
            File: \(material.name)
            """
            if let answer = try? await LanguageModelSession(instructions: Self.videoInstructions)
                .respond(to: prompt, generating: VideoTodo.self) {
                let title = TodoText.tidyTitle(answer.content.title)
                if !title.isEmpty { return (title, true) }
            }
            return (fallback, false)
        }
        #endif
        return (fallback, true)
    }

    /// The to-dos a screenshot or caption lists, with any durations written beside them.
    private static func listedTodos(in text: String, caption: String) async -> [(title: String, duration: TimeInterval?)] {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            if let answer = try? await LanguageModelSession(instructions: Self.listInstructions)
                .respond(to: String(body.prefix(4000)), generating: ListedTodos.self) {
                let items = answer.content.todos.compactMap { item -> (title: String, duration: TimeInterval?)? in
                    let duration = item.duration.flatMap(TodoText.duration(in:)) ?? TodoText.duration(in: item.title)
                    let title = TodoText.tidyTitle(TodoText.removingTrailingDuration(from: item.title))
                    return title.isEmpty ? nil : (title, duration)
                }
                if !items.isEmpty { return items }
            }
        }
        #endif
        // Without the model, a numbered or bulleted line is a to-do.
        return TodoText.listItems(in: body)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
@Generable
private struct VideoTodo {
    @Guide(description: "What the viewer should do, as a short imperative to-do of 2 to 8 words")
    var title: String
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
private struct ListedTodo {
    @Guide(description: "A short imperative to-do, like 'Build GPT's tokenizer'")
    var title: String
    @Guide(description: "The duration written next to it, like '14:32' or '20 min', if there is one")
    var duration: String?
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
private struct ListedTodos {
    @Guide(description: "Each separate thing to do, in the post's order")
    var todos: [ListedTodo]
}

@available(macOS 26.0, iOS 26.0, *)
@Generable
private struct ListName {
    @Guide(description: "A name for the to-do list in 2 to 5 words, like 'Rebuild AI projects' or 'Morning mobility'")
    var name: String
}
#endif
