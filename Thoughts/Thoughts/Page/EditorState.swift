import SwiftUI
import Observation
import ThoughtsKit

/// The "/" menu while it's open: which block it's for and what's been typed after the slash.
struct SlashState: Equatable {
    var blockID: UUID
    var query: String
    /// Opened with the + button instead of typing "/", so there's no "/word" to remove.
    var fromButton: Bool
}

/// Per-page editing state: which block has the keyboard, where the cursor should go next,
/// and the "/" menu.
@Observable
final class EditorState {
    var focusedBlockID: UUID?
    var pending: CursorTarget?
    var slash: SlashState?
    var focusTitle = false

    var slashResults: [SlashCommand] {
        guard let slash else { return [] }
        return SlashCommands.filter(slash.query)
    }
}

/// The editing actions for one page's blocks. Views call these; they change the model and
/// tell the editor where the cursor goes.
struct BlockActions {
    let model: AppModel
    let editor: EditorState
    let pageID: UUID

    private var blocks: [Block] { model.page(pageID)?.blocks ?? [] }

    private func index(_ id: UUID) -> Int? {
        blocks.firstIndex { $0.id == id }
    }

    func textChanged(_ id: UUID, _ newText: String) {
        var follow: CursorTarget?
        var finalText = newText
        var kind: BlockKind = .text
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            blocks[i].text = newText
            if let match = MarkdownShortcut.match(newText, in: blocks[i].kind) {
                blocks[i].turn(into: match.kind)
                blocks[i].text = match.rest
                blocks[i].checked = match.checked
                finalText = match.rest
                if match.kind == .divider {
                    let next = Block(indent: blocks[i].indent)
                    blocks.insert(next, at: i + 1)
                    follow = CursorTarget(blockID: next.id, offset: 0)
                } else {
                    follow = CursorTarget(blockID: id, offset: 0)
                }
            }
            kind = blocks[i].kind
        }
        if let follow { editor.pending = follow }

        if kind.hasText, kind != .code, let active = SlashCommands.activeQuery(in: finalText),
           !SlashCommands.filter(active.query).isEmpty {
            editor.slash = SlashState(blockID: id, query: active.query, fromButton: false)
        } else if editor.slash?.blockID == id, editor.slash?.fromButton == false {
            editor.slash = nil
        }
    }

    func pressReturn(_ id: UUID, offset: Int) {
        if let slash = editor.slash, slash.blockID == id, let first = editor.slashResults.first {
            apply(first)
            return
        }
        var target: CursorTarget?
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            target = BlockEditing.pressReturn(&blocks, at: i, offset: offset)
        }
        editor.slash = nil
        if let target { editor.pending = target }
    }

    func backspaceAtStart(_ id: UUID) -> Bool {
        guard let i = index(id) else { return false }
        var target: CursorTarget?
        let before = blocks
        var after = before
        target = BlockEditing.backspaceAtStart(&after, at: i)
        if let target {
            model.updateBlocks(pageID) { $0 = after }
            editor.pending = target
            return true
        }
        // Backspace on an empty first line goes up to the title.
        if i == 0 && before[i].text.isEmpty {
            editor.focusTitle = true
            return true
        }
        return false
    }

    func toggleChecked(_ id: UUID) {
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            blocks[i].checked.toggle()
        }
    }

    func toggleCollapsed(_ id: UUID) {
        model.updateBlocks(pageID) { BlockEditing.toggleCollapsed(&$0, id: id) }
    }

    func turn(_ id: UUID, into kind: BlockKind) {
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            blocks[i].turn(into: kind)
        }
    }

    func indent(_ id: UUID) {
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            BlockEditing.indent(&blocks, at: i)
        }
    }

    func outdent(_ id: UUID) {
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            BlockEditing.outdent(&blocks, at: i)
        }
    }

    func moveUp(_ id: UUID) {
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            BlockEditing.moveUp(&blocks, at: i)
        }
        keepFocus(id)
    }

    func moveDown(_ id: UUID) {
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            BlockEditing.moveDown(&blocks, at: i)
        }
        keepFocus(id)
    }

    /// After a block moves, puts the keyboard back on it (with the cursor at the end) in case it was lost.
    private func keepFocus(_ id: UUID) {
        guard editor.focusedBlockID == id, let block = blocks.first(where: { $0.id == id }) else { return }
        editor.pending = CursorTarget(blockID: id, offset: block.text.utf16.count)
    }

    func duplicate(_ id: UUID) {
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            BlockEditing.duplicate(&blocks, at: i)
        }
    }

    func delete(_ id: UUID) {
        var target: CursorTarget?
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            target = BlockEditing.delete(&blocks, at: i)
        }
        if editor.focusedBlockID == id {
            if let target { editor.pending = target } else { editor.focusedBlockID = nil }
        }
        if editor.slash?.blockID == id { editor.slash = nil }
    }

    func setCalloutIcon(_ id: UUID, _ icon: String) {
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            blocks[i].icon = icon
        }
    }

    /// Focuses the last line, adding an empty text line first if the last block isn't one.
    func focusEnd() {
        var target: UUID?
        model.updateBlocks(pageID) { blocks in
            if let last = blocks.last, last.kind == .text, last.text.isEmpty, last.indent == 0 {
                target = last.id
            } else {
                let block = Block()
                blocks.append(block)
                target = block.id
            }
        }
        if let target { editor.pending = CursorTarget(blockID: target, offset: 0) }
    }

    /// Focuses the first line, adding one if the page is empty.
    func focusStart() {
        if let first = blocks.first, first.kind.hasText {
            editor.pending = CursorTarget(blockID: first.id, offset: 0)
            return
        }
        let block = Block()
        model.updateBlocks(pageID) { $0.insert(block, at: 0) }
        editor.pending = CursorTarget(blockID: block.id, offset: 0)
    }

    /// Opens the "/" menu from the + button for the focused block.
    func openInsertMenu() {
        guard let id = editor.focusedBlockID else { return }
        editor.slash = SlashState(blockID: id, query: "", fromButton: true)
    }

    /// Runs a "/" menu command on the block it was opened for.
    func apply(_ command: SlashCommand) {
        guard let slash = editor.slash else { return }
        editor.slash = nil
        let id = slash.blockID
        var newPage: UUID?
        switch command.action {
        case .newPage, .newDatabase:
            let kind: PageKind = command.action == .newDatabase ? .database : .document
            // The link goes where the "/" was typed, not at the end of the page.
            model.mutate { newPage = $0.createSubpage(in: pageID, kind: kind, addLink: false) }
        case .turnInto:
            break
        }
        var follow: CursorTarget?
        model.updateBlocks(pageID) { blocks in
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
            if !slash.fromButton {
                blocks[i].text = SlashCommands.removingQuery(from: blocks[i].text)
            }
            let emptyText = blocks[i].text.isEmpty && blocks[i].kind.hasText
            switch command.action {
            case .turnInto(let kind):
                if emptyText {
                    blocks[i].turn(into: kind)
                    if kind == .divider {
                        let next = Block(indent: blocks[i].indent)
                        blocks.insert(next, at: i + 1)
                        follow = CursorTarget(blockID: next.id, offset: 0)
                    } else {
                        follow = CursorTarget(blockID: id, offset: 0)
                    }
                } else {
                    let newID = BlockEditing.insert(kind, &blocks, after: i)
                    follow = CursorTarget(blockID: newID, offset: 0)
                }
            case .newPage, .newDatabase:
                guard let newPage else { return }
                if emptyText {
                    blocks[i].turn(into: .pageLink)
                    blocks[i].text = ""
                    blocks[i].linkedPageID = newPage
                } else {
                    let link = Block(kind: .pageLink, indent: blocks[i].indent, linkedPageID: newPage)
                    blocks.insert(link, at: BlockEditing.subtree(blocks, at: i).upperBound)
                }
            }
        }
        if let follow {
            editor.pending = follow
        }
        if let newPage {
            model.open(newPage)
        }
    }
}
