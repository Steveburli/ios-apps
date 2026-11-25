import SwiftUI
import ThoughtsKit

/// Recents, favorites and every page as a tree, plus a button for a new page.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showingTemplates = false
    @State private var moving: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                let recents = model.workspace.recents()
                if !recents.isEmpty {
                    section("Jump back in") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(recents) { page in
                                    NavigationLink(value: page.id) { RecentCard(page: page) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .scrollClipDisabled()
                    }
                }

                let favorites = model.workspace.favorites
                if !favorites.isEmpty {
                    section("Favorites") {
                        VStack(spacing: 0) {
                            ForEach(favorites) { page in
                                PageTreeRow(page: page, depth: 0, showsChildren: false, moving: $moving)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }

                section("Private") {
                    VStack(spacing: 0) {
                        ForEach(model.workspace.roots) { page in
                            PageTree(page: page, depth: 0, moving: $moving)
                        }
                        Button {
                            model.open(model.newPage())
                        } label: {
                            Label("Add a page", systemImage: "plus")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                }

                section("Start from a template") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Templates.all) { template in
                                Button {
                                    if let id = model.addTemplate(template.id) { model.open(id) }
                                } label: {
                                    TemplateChip(template: template)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(.vertical, 12)
        }
        .background(Theme.paper)
        .navigationTitle("Thoughts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { model.open(model.newPage()) } label: { Label("New page", systemImage: "doc.text") }
                    Button { model.open(model.newPage(kind: .database)) } label: { Label("New database", systemImage: "tablecells") }
                    Divider()
                    ForEach(Templates.all) { template in
                        Button("\(template.icon)  \(template.title)") {
                            if let id = model.addTemplate(template.id) { model.open(id) }
                        }
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                } primaryAction: {
                    model.open(model.newPage())
                }
                .accessibilityLabel("New page")
            }
        }
        .sheet(item: Binding(get: { moving.map(MoveTarget.init) }, set: { moving = $0?.id })) { target in
            MovePageSheet(pageID: target.id)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 18)
            content()
        }
    }
}

struct MoveTarget: Identifiable {
    let id: UUID
}

/// A page and, when open, the pages inside it.
struct PageTree: View {
    @Environment(AppModel.self) private var model
    let page: Page
    let depth: Int
    @Binding var moving: UUID?

    var body: some View {
        PageTreeRow(page: page, depth: depth, showsChildren: true, moving: $moving)
        if model.expanded.contains(page.id) && page.kind == .document {
            let children = model.workspace.children(of: page.id)
            if children.isEmpty {
                Text("No pages inside")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.faint)
                    .padding(.leading, CGFloat(depth + 1) * 18 + 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(children) { child in
                    PageTree(page: child, depth: depth + 1, moving: $moving)
                }
            }
        }
    }
}

/// One row of the page tree: a chevron to open it, the icon and title, and quick actions.
struct PageTreeRow: View {
    @Environment(AppModel.self) private var model
    let page: Page
    let depth: Int
    let showsChildren: Bool
    @Binding var moving: UUID?

    var body: some View {
        let open = model.expanded.contains(page.id)
        HStack(spacing: 6) {
            if showsChildren && page.kind == .document {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if open { model.expanded.remove(page.id) } else { model.expanded.insert(page.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 26, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? "Close" : "Open")
            } else {
                Color.clear.frame(width: 26, height: 30)
            }
            NavigationLink(value: page.id) {
                HStack(spacing: 8) {
                    PageIcon(page: page, size: 17)
                    Text(page.displayTitle)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(page.title.isEmpty ? Theme.muted : Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if page.kind == .document {
                Button {
                    model.open(model.newPage(in: page.id))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 32, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a page inside \(page.displayTitle)")
            }
        }
        .padding(.leading, CGFloat(depth) * 18)
        .padding(.vertical, 2)
        .contextMenu { PageMenuItems(pageID: page.id, moving: $moving) }
    }
}

/// The actions shared by a page's touch-and-hold menu and its "…" menu.
struct PageMenuItems: View {
    @Environment(AppModel.self) private var model
    let pageID: UUID
    @Binding var moving: UUID?
    var afterTrash: () -> Void = {}

    var body: some View {
        if let page = model.page(pageID) {
            Button {
                model.toggleFavorite(pageID)
            } label: {
                Label(page.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: page.isFavorite ? "star.slash" : "star")
            }
            Button { model.duplicate(pageID) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            if !model.workspace.isRow(pageID) {
                Button { moving = pageID } label: { Label("Move to…", systemImage: "arrow.turn.up.right") }
            }
            ShareLink(item: MarkdownExport.markdown(for: pageID, in: model.workspace),
                      subject: Text(page.displayTitle)) {
                Label("Share as Markdown", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(role: .destructive) {
                model.trash(pageID)
                afterTrash()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }
}

struct RecentCard: View {
    let page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let cover = page.cover {
                    Rectangle().fill(Theme.cover(cover))
                } else {
                    Rectangle().fill(Theme.sunk)
                }
                PageIcon(page: page, size: 22)
                    .padding(6)
                    .background(Theme.surface.opacity(page.icon == nil ? 1 : 0), in: RoundedRectangle(cornerRadius: 6))
                    .offset(x: 12, y: 14)
            }
            .frame(height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(page.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(page.edited.relativeText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 22)
            .padding(.bottom, 10)
        }
        .frame(width: 150, height: 150)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
    }
}

struct TemplateChip: View {
    let template: PageTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(template.icon).font(.system(size: 24))
            Text(template.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(template.summary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(width: 150, height: 120, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
    }
}

/// Picks where a page goes: the top level or inside another page.
struct MovePageSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pageID: UUID
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            List {
                if model.page(pageID)?.parentID != nil {
                    Button {
                        model.move(pageID, to: nil)
                        dismiss()
                    } label: {
                        Label("Top level", systemImage: "arrow.up.to.line")
                    }
                }
                Section("Pages") {
                    ForEach(targets) { target in
                        Button {
                            model.move(pageID, to: target.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                PageIcon(page: target, size: 17)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.displayTitle).foregroundStyle(Theme.ink)
                                    let path = model.workspace.path(to: target.id).dropLast().map(\.displayTitle)
                                    if !path.isEmpty {
                                        Text(path.joined(separator: " / "))
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $filter, prompt: "Find a page")
            .navigationTitle("Move \(model.page(pageID)?.displayTitle ?? "page") to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private var targets: [Page] {
        let all = model.workspace.moveTargets(for: pageID)
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.displayTitle.localizedCaseInsensitiveContains(q) }
    }
}
