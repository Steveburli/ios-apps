import SwiftUI
import ThoughtsKit

/// A page: its cover, icon and title, then its writing, or its table or board for a database.
struct PageScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pageID: UUID
    @State private var editor = EditorState()
    @State private var moving: UUID?
    @State private var pickingIcon = false
    @State private var pickingCover = false

    var body: some View {
        if let page = model.page(pageID) {
            content(page)
        } else {
            ContentUnavailableView("Page deleted", systemImage: "doc.questionmark",
                                   description: Text("This page was deleted for good."))
        }
    }

    private var actions: BlockActions {
        BlockActions(model: model, editor: editor, pageID: pageID)
    }

    private func content(_ page: Page) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.workspace.isInTrash(pageID) {
                        trashBanner
                    }
                    PageHeader(pageID: pageID, editor: editor, actions: actions,
                               pickingIcon: $pickingIcon, pickingCover: $pickingCover)
                    if let database = model.workspace.database(of: pageID) {
                        RowProperties(rowID: pageID, databaseID: database.id)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        Rectangle().fill(Theme.line).frame(height: 1)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                    }
                    if page.kind == .database {
                        DatabaseBody(databaseID: pageID)
                    } else {
                        blockList(page)
                            .padding(.horizontal, 20)
                        if page.blocks.isEmpty && model.workspace.children(of: pageID).isEmpty {
                            EmptyPageSuggestions(pageID: pageID, actions: actions)
                                .padding(.horizontal, 20)
                        }
                        // Tapping below the last block starts a new line.
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 220)
                            .contentShape(Rectangle())
                            .onTapGesture { actions.focusEnd() }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: editor.pending) { _, target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target.blockID) }
            }
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editor.focusedBlockID != nil {
                VStack(spacing: 0) {
                    if editor.slash != nil && !editor.slashResults.isEmpty {
                        SlashMenu(editor: editor, actions: actions)
                    }
                    EditorToolbar(pageID: pageID, editor: editor, actions: actions)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: editor.focusedBlockID == nil)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Breadcrumb(pageID: pageID)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.toggleFavorite(pageID)
                } label: {
                    Image(systemName: page.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(page.isFavorite ? Color.yellow : Theme.ink)
                }
                .accessibilityLabel(page.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    PageMenuItems(pageID: pageID, moving: $moving, afterTrash: { dismiss() })
                    if page.kind == .document && page.blocks.isEmpty && model.workspace.children(of: pageID).isEmpty
                        && !model.workspace.isRow(pageID) {
                        Button {
                            model.update(pageID) { $0.kind = .database; $0.database = DatabaseSchema.starter() }
                        } label: {
                            Label("Turn into database", systemImage: "tablecells")
                        }
                    }
                    Divider()
                    Text("\(page.wordCount) words · edited \(page.edited.relativeText)")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Page options")
            }
        }
        .sheet(item: Binding(get: { moving.map(MoveTarget.init) }, set: { moving = $0?.id })) { target in
            MovePageSheet(pageID: target.id)
        }
        .sheet(isPresented: $pickingIcon) {
            IconPicker(pageID: pageID)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $pickingCover) {
            CoverPicker(pageID: pageID)
                .presentationDetents([.height(320)])
        }
        .onAppear {
            model.markOpened(pageID)
            Screenshots.prepareEditor(editor, page: page)
        }
    }

    private func blockList(_ page: Page) -> some View {
        let blocks = page.blocks
        let visible = BlockEditing.visibleIndices(blocks)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(visible, id: \.self) { index in
                BlockRow(block: blocks[index],
                         number: blocks[index].kind == .numbered ? BlockEditing.number(blocks, at: index) : 0,
                         actions: actions, editor: editor)
            }
        }
    }

    private var trashBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
            Text("This page is in the Trash.")
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Button("Restore") { model.restore(pageID) }
                .font(.system(size: 14, weight: .semibold))
            Button("Delete", role: .destructive) {
                dismiss()
                model.deleteForever(pageID)
            }
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(.white)
        .tint(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: 0xC2410C))
    }
}

/// "Personal home / Reading list" in the navigation bar.
struct Breadcrumb: View {
    @Environment(AppModel.self) private var model
    let pageID: UUID

    var body: some View {
        let path = model.workspace.path(to: pageID)
        HStack(spacing: 4) {
            ForEach(Array(path.enumerated()), id: \.element.id) { index, page in
                if index > 0 {
                    Text("/").foregroundStyle(Theme.faint)
                }
                if let icon = page.icon { Text(icon).font(.system(size: 13)) }
                Text(page.displayTitle)
                    .foregroundStyle(index == path.count - 1 ? Theme.ink : Theme.muted)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 14, weight: .medium))
        .frame(maxWidth: 240)
    }
}

/// Cover, icon and title.
struct PageHeader: View {
    @Environment(AppModel.self) private var model
    let pageID: UUID
    let editor: EditorState
    let actions: BlockActions
    @Binding var pickingIcon: Bool
    @Binding var pickingCover: Bool
    @FocusState private var titleFocused: Bool

    var body: some View {
        let page = model.page(pageID)
        VStack(alignment: .leading, spacing: 0) {
            if let cover = page?.cover {
                Button { pickingCover = true } label: {
                    Rectangle().fill(Theme.cover(cover)).frame(height: 150)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change cover")
            }
            VStack(alignment: .leading, spacing: 8) {
                if let icon = page?.icon {
                    Button { pickingIcon = true } label: {
                        Text(icon).font(.system(size: 60))
                    }
                    .buttonStyle(.plain)
                    .offset(y: page?.cover != nil ? -38 : 0)
                    .padding(.bottom, page?.cover != nil ? -38 : 0)
                    .accessibilityLabel("Change icon")
                }
                if page?.icon == nil || page?.cover == nil {
                    HStack(spacing: 14) {
                        if page?.icon == nil {
                            Button { model.update(pageID) { $0.icon = IconPicker.random() } } label: {
                                Label("Add icon", systemImage: "face.smiling")
                            }
                        }
                        if page?.cover == nil {
                            Button { model.update(pageID) { $0.cover = Int.random(in: 0..<Theme.covers.count) } } label: {
                                Label("Add cover", systemImage: "photo")
                            }
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .buttonStyle(.plain)
                }
                TextField("Untitled", text: titleBinding, axis: .vertical)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .focused($titleFocused)
                    .submitLabel(.next)
                if let page, page.kind == .document {
                    let progress = page.todoProgress
                    if progress.total > 0 {
                        ProgressLine(done: progress.done, total: progress.total)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, page?.cover == nil ? 16 : 12)
            .padding(.bottom, 14)
        }
        .onChange(of: editor.focusTitle) { _, want in
            if want {
                titleFocused = true
                editor.focusTitle = false
            }
        }
        .onAppear {
            // A brand-new empty page starts with the title ready to type.
            if let page, page.title.isEmpty, page.blocks.isEmpty, Date().timeIntervalSince(page.created) < 3,
               !Screenshots.isActive {
                titleFocused = true
            }
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { model.page(pageID)?.title ?? "" },
            set: { newValue in
                // Return in the title goes to the first line of the page.
                if newValue.contains("\n") {
                    let cleaned = newValue.replacingOccurrences(of: "\n", with: "")
                    model.update(pageID) { $0.title = cleaned }
                    if model.page(pageID)?.kind == .document { actions.focusStart() } else { titleFocused = false }
                } else {
                    model.update(pageID) { $0.title = newValue }
                }
            }
        )
    }
}

/// "3 of 5 done" with a thin bar, under the title of a page with to-dos.
struct ProgressLine: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(Theme.accent)
                .frame(maxWidth: 120)
            Text("\(done) of \(total) done")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
    }
}

/// Shown on a new empty page: start writing, or fill it from a template.
struct EmptyPageSuggestions: View {
    @Environment(AppModel.self) private var model
    let pageID: UUID
    let actions: BlockActions

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { actions.focusStart() } label: {
                row("square.and.pencil", "Start writing")
            }
            Text("Or start with")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.top, 14)
                .padding(.bottom, 4)
            ForEach(Templates.all.filter { !["projects", "reading"].contains($0.id) }) { template in
                Button { model.apply(template: template.id, to: pageID) } label: {
                    HStack(spacing: 10) {
                        Text(template.icon).frame(width: 24)
                        Text(template.title).foregroundStyle(Theme.ink)
                    }
                    .font(.system(size: 16))
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
            }
            if !model.workspace.isRow(pageID) {
                Button {
                    model.update(pageID) { $0.kind = .database; $0.database = DatabaseSchema.starter() }
                } label: {
                    row("tablecells", "Database")
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func row(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Theme.muted).frame(width: 24)
            Text(title).foregroundStyle(Theme.ink)
        }
        .font(.system(size: 16))
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
