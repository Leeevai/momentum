import MomentumCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Turns saved videos (an Instagram reel, a TikTok, any clip), screenshots of a post, or a pasted
/// caption into to-dos: each video becomes one, as long as the video, named on the device; each
/// keeps the post's link. They're added as milestones to a new goal or an existing one.
struct ImportTodosSheet: View {
    @Environment(GoalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var initialLink: URL?

    @State private var files: [URL] = []
    @State private var linkText = ""
    @State private var caption = ""
    @State private var status: String?
    @State private var todos: [FoundTodo] = []
    @State private var skipped: Set<UUID> = []
    @State private var listName = ""
    @State private var destination: UUID?
    @State private var isReviewing = false
    @State private var choosesFiles = false
    @State private var pickedMedia: [PhotosPickerItem] = []
    @State private var problem: String?
    /// Copies of what was added, readable for as long as the sheet is open; removed with it.
    @State private var folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-import-\(UUID().uuidString)")

    private static let fileTypes: [UTType] = [.movie, .video, .audio, .image]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isReviewing { review } else { collect }
                }
                .padding([.horizontal, .bottom], 24)
            }
            Divider()
            footer
        }
        .sheetFrame(width: 580, height: 680)
        .background(Aurora(animates: false))
        .fileImporter(isPresented: $choosesFiles, allowedContentTypes: Self.fileTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { add(urls) }
        }
        .onChange(of: pickedMedia) { _, items in loadPicked(items) }
        .dropDestination(for: URL.self) { urls, _ in
            add(urls)
            return !urls.isEmpty
        }
        .onAppear {
            if let initialLink, linkText.isEmpty { linkText = initialLink.absoluteString }
            #if DEBUG
            addRequestedFiles()
            #endif
        }
        .onDisappear { try? FileManager.default.removeItem(at: folder) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isReviewing ? "Found \(todos.count) to-do\(todos.count == 1 ? "" : "s")" : "To-dos from videos")
                .font(.title.weight(.bold))
            Text(isReviewing
                 ? "Rename, untick what you don't want, and pick where they go."
                 : "Add the reels, videos or screenshots you saved. Each video becomes a to-do as long as the video, named by on-device AI. Nothing leaves this device.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
    }

    // MARK: - Collecting

    private var collect: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button { choosesFiles = true } label: { Label("Choose Files…", systemImage: "folder") }
                        .secondaryActionStyle(.accent, compact: true)
                    PhotosPicker(selection: $pickedMedia, matching: .any(of: [.videos, .images])) {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                    .secondaryActionStyle(.accent, compact: true)
                }
                if files.isEmpty {
                    Text(Self.instagramHelp)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(files, id: \.self) { file in fileRow(file) }
                }
            }
            .glassCard(padding: 16)

            VStack(alignment: .leading, spacing: 10) {
                Label("Link to the post", systemImage: "link").font(.headline)
                TextField("instagram.com/reel/…", text: $linkText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Text("Kept on each to-do, to open the video again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard(padding: 16)

            VStack(alignment: .leading, spacing: 10) {
                Label("Caption", systemImage: "text.quote").font(.headline)
                TextEditor(text: $caption)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: GlassTokens.controlRadius, style: .continuous).fill(Color.primary.opacity(0.05)))
                Text("Optional. Paste the post's text: it helps name the videos, and a list in it becomes to-dos too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard(padding: 16)

            if let note = TodoFinder.modelNote {
                Label(note, systemImage: "sparkles")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private static let instagramHelp = """
        From Instagram or TikTok, save the video first (Share, then Download or Save, or a screen \
        recording) and add it here, along with screenshots of a carousel. Apps can't open a post from \
        its link, but paste the link below to keep it on each to-do.
        """

    private func fileRow(_ file: URL) -> some View {
        let isVideo = UTType(filenameExtension: file.pathExtension)?.conforms(to: .audiovisualContent) ?? false
        return HStack(spacing: 10) {
            Image(systemName: isVideo ? "play.rectangle.fill" : "photo")
                .foregroundStyle(Color.accent)
                .frame(width: 22)
            Text(file.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                files.removeAll { $0 == file }
                try? FileManager.default.removeItem(at: file)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(file.lastPathComponent)")
        }
    }

    // MARK: - Reviewing

    private var review: some View {
        let milestoneGoals = store.engine.activeGoals.filter { $0.kind == .milestones }
        let chosen = todos.filter { !skipped.contains($0.id) }
        let total = chosen.compactMap(\.duration).reduce(0, +)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Add to", selection: $destination) {
                    Text("A new goal").tag(UUID?.none)
                    ForEach(milestoneGoals) { goal in
                        Text(goal.name).tag(UUID?.some(goal.id))
                    }
                }
                if destination == nil {
                    TextField("Goal name", text: $listName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .glassCard(padding: 16)

            VStack(alignment: .leading, spacing: 4) {
                ForEach($todos) { $todo in
                    todoRow($todo)
                    if todo.id != todos.last?.id { Divider() }
                }
                if total > 0 {
                    Text("\(Formatting.duration(total)) in all")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
            }
            .glassCard(padding: 16)
        }
    }

    private func todoRow(_ todo: Binding<FoundTodo>) -> some View {
        let id = todo.wrappedValue.id
        let included = Binding(get: { !skipped.contains(id) }, set: { isOn in
            if isOn { skipped.remove(id) } else { skipped.insert(id) }
        })
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            // A checkbox on the Mac, a switch on iPhone and iPad.
            Toggle("Include", isOn: included)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                TextField("To-do", text: todo.title)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                Text(todo.wrappedValue.source)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let duration = todo.wrappedValue.duration {
                Label(Formatting.clock(duration), systemImage: "clock")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .opacity(included.wrappedValue ? 1 : 0.5)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let status {
                ProgressView().controlSize(.small)
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isReviewing {
                Button("Back") { withAnimation { isReviewing = false } }
                Button {
                    save()
                } label: {
                    let count = todos.count - skipped.count
                    Label("Add \(count) To-do\(count == 1 ? "" : "s")", systemImage: "checklist")
                }
                .primaryActionStyle(.accent)
                .disabled(todos.count == skipped.count)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    find()
                } label: {
                    Label("Find To-dos", systemImage: "sparkles")
                }
                .primaryActionStyle(.accent)
                .disabled(status != nil || (files.isEmpty && caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    // MARK: - Actions

    /// Keeps a copy of each file, so it can still be read once the picker's access ends.
    private func add(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let copy = try? Self.copy(url, into: folder) { files.append(copy) }
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickedMedia = []
        Task {
            for item in items {
                if let media = try? await item.loadTransferable(type: PickedMedia.self),
                   let copy = try? Self.copy(media.url, into: folder) {
                    files.append(copy)
                    try? FileManager.default.removeItem(at: media.url)
                } else {
                    problem = "One of the items couldn't be read from Photos."
                }
            }
        }
    }

    private func find() {
        problem = nil
        let link = TodoText.link(from: linkText)
        status = "Getting started…"
        Task {
            let found = await TodoFinder.todos(in: files, caption: caption, link: link) { status = $0 }
            let name = await TodoFinder.listName(for: found, caption: caption)
            status = nil
            if found.isEmpty {
                problem = "No to-dos found. Try adding the video itself, or paste the caption."
                return
            }
            todos = found
            skipped = []
            listName = name
            withAnimation { isReviewing = true }
            #if DEBUG
            if ProcessInfo.processInfo.environment["MOMENTUM_IMPORT_SAVE"] != nil { save() }
            #endif
        }
    }

    #if DEBUG
    /// Simulator runs, without the pickers: `MOMENTUM_IMPORT_FILES` names files in the app's
    /// temporary folder to add, `MOMENTUM_IMPORT_CAPTION` fills the caption, `MOMENTUM_IMPORT_FIND`
    /// starts looking, and `MOMENTUM_IMPORT_SAVE` adds what was found.
    private func addRequestedFiles() {
        let environment = ProcessInfo.processInfo.environment
        guard files.isEmpty, let names = environment["MOMENTUM_IMPORT_FILES"] else { return }
        add(names.split(separator: ",").map { FileManager.default.temporaryDirectory.appendingPathComponent(String($0)) })
        caption = environment["MOMENTUM_IMPORT_CAPTION"] ?? caption
        if environment["MOMENTUM_IMPORT_FIND"] != nil { find() }
    }
    #endif

    private func save() {
        let chosen = todos.filter { !skipped.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let name = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newGoal = Goal(name: name.isEmpty ? "Saved videos" : name, symbol: "play.rectangle.on.rectangle",
                           color: .suggested(besides: store.data.goals),
                           kind: .milestones, target: 0)
        let target = destination ?? newGoal.id
        store.perform("Add To-dos") { $0.addTodos(chosen, to: destination, orNew: newGoal) }
        dismiss()
        store.select(target)
    }

    static func copy(_ url: URL, into folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var destination = folder.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let stem = url.deletingPathExtension().lastPathComponent
            destination = folder.appendingPathComponent("\(stem) \(counter)").appendingPathExtension(url.pathExtension)
            counter += 1
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}

/// A video or image from the Photos picker, copied out of the picker's temporary file.
private struct PickedMedia: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in try PickedMedia(copying: received.file) }
        FileRepresentation(importedContentType: .image) { received in try PickedMedia(copying: received.file) }
    }

    init(copying file: URL) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("momentum-picked-\(UUID().uuidString)")
        url = try ImportTodosSheet.copy(file, into: folder)
    }
}
