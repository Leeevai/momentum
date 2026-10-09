import MomentumCore
import SwiftUI
import UniformTypeIdentifiers

/// A goal's links: docs, repos, apps and files. Drop a URL or file onto the card to add it.
struct LinksSection: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Links", systemImage: "link", trailing: AnyView(
                Button {
                    store.sheet = .link(goalID: goal.id, link: nil)
                } label: {
                    Label("Add link", systemImage: "plus")
                }
                .secondaryActionStyle(goal.tint, compact: true)
            ))
            if goal.links.isEmpty {
                Text("Attach what you need to get started: a doc, a repo, a course, a playlist, or a local project folder. Mark a link with \(Image(systemName: "bolt.fill")) to open it whenever a focus session starts. You can also drop links and files here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(goal.links) { link in
                        LinkRow(goal: goal, link: link)
                    }
                }
            }
        }
        .glassCard(tint: goal.tint, highlighted: isTargeted)
        .onDrop(of: [.url, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let goalID = goal.id
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    let bookmark = url.isFileURL ? LinkOpener.bookmark(for: url) : nil
                    let link = GoalLink(title: "", url: url, bookmark: bookmark)
                    store.perform("Add Link") { $0.upsertLink(link, in: goalID) }
                }
            }
        }
        return !providers.isEmpty
    }
}

private struct LinkRow: View {
    @Environment(GoalStore.self) private var store
    let goal: Goal
    let link: GoalLink
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            LinkIcon(link: link)
            VStack(alignment: .leading, spacing: 1) {
                Text(link.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(link.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if goal.kind == .time {
                Button {
                    var updated = link
                    updated.opensWithFocus.toggle()
                    store.perform("Edit Link") { $0.upsertLink(updated, in: goal.id) }
                } label: {
                    Image(systemName: link.opensWithFocus ? "bolt.fill" : "bolt")
                        .foregroundStyle(link.opensWithFocus ? goal.tint : .secondary)
                }
                .buttonStyle(.borderless)
                .help(link.opensWithFocus ? "Opens when a focus session starts" : "Open when a focus session starts")
            }
            Button("Open") { LinkOpener.open(link) }
                .secondaryActionStyle(goal.tint, compact: true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(isHovered ? 0.05 : 0)))
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { LinkOpener.open(link) }
        .contextMenu {
            Button("Open") { LinkOpener.open(link) }
            Button("Edit…") { store.sheet = .link(goalID: goal.id, link: link) }
            Button("Copy Address") { Pasteboard.copy(link.url.absoluteString) }
            Divider()
            Button("Remove", role: .destructive) {
                store.perform("Remove Link") { $0.removeLink(link.id, from: goal.id) }
            }
        }
    }
}
