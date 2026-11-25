import Foundation

/// Where the cursor should go after an edit: a block, and a UTF-16 offset into its text
/// (the units UITextView counts in).
public struct CursorTarget: Equatable, Sendable {
    public var blockID: UUID
    public var offset: Int

    public init(blockID: UUID, offset: Int) {
        self.blockID = blockID
        self.offset = offset
    }
}

/// The editing rules for a page's flat list of blocks. Nesting is each block's `indent`:
/// a block's children are the blocks right after it with a deeper indent.
public enum BlockEditing {
    /// The block and its children: `index ..< end`.
    public static func subtree(_ blocks: [Block], at index: Int) -> Range<Int> {
        guard blocks.indices.contains(index) else { return index..<index }
        let indent = blocks[index].indent
        var end = index + 1
        while end < blocks.count, blocks[end].indent > indent { end += 1 }
        return index..<end
    }

    /// Indices of blocks that show, leaving out children of closed toggles.
    public static func visibleIndices(_ blocks: [Block]) -> [Int] {
        var result: [Int] = []
        var hideDeeperThan: Int?
        for (i, block) in blocks.enumerated() {
            if let limit = hideDeeperThan {
                if block.indent > limit { continue }
                hideDeeperThan = nil
            }
            result.append(i)
            if block.kind == .toggle && block.collapsed { hideDeeperThan = block.indent }
        }
        return result
    }

    /// The number shown before a numbered-list item: 1 plus the numbered items right above it
    /// at the same indent (deeper items in between don't break the run).
    public static func number(_ blocks: [Block], at index: Int) -> Int {
        guard blocks.indices.contains(index) else { return 1 }
        let indent = blocks[index].indent
        var count = 1
        var i = index - 1
        while i >= 0 {
            let b = blocks[i]
            if b.indent > indent { i -= 1; continue }
            if b.indent < indent || b.kind != .numbered { break }
            count += 1
            i -= 1
        }
        return count
    }

    /// Return was pressed in a block with the cursor at `offset` (UTF-16).
    /// - An empty list item steps out: it moves left one level, or turns into text at the left edge.
    /// - At the very start of a line with text, a new empty line goes in above.
    /// - Otherwise the text after the cursor moves to a new block below. Lists continue as
    ///   the same kind; everything else continues as text. An open toggle puts it inside.
    @discardableResult
    public static func pressReturn(_ blocks: inout [Block], at index: Int, offset: Int) -> CursorTarget? {
        guard blocks.indices.contains(index) else { return nil }
        let block = blocks[index]
        if block.kind.continuesOnReturn && block.text.isEmpty {
            if block.indent > 0 {
                shiftSubtree(&blocks, at: index, by: -1)
            } else {
                blocks[index].turn(into: .text)
            }
            return CursorTarget(blockID: block.id, offset: 0)
        }
        let length = block.text.utf16.count
        let cut = max(0, min(offset, length))
        let continuing: BlockKind = block.kind.continuesOnReturn ? block.kind : .text

        if cut == 0 && length > 0 {
            var above = Block(kind: block.kind.isHeading ? .text : continuing, indent: block.indent)
            if above.kind == .callout { above.kind = .text }
            blocks.insert(above, at: index)
            return CursorTarget(blockID: block.id, offset: 0)
        }

        let head = block.text.utf16Prefix(cut)
        let tail = block.text.utf16Suffix(from: cut)
        blocks[index].text = head
        var next = Block(kind: continuing, text: tail, indent: block.indent)
        var insertAt = index + 1
        if block.kind == .toggle {
            if block.collapsed {
                insertAt = subtree(blocks, at: index).upperBound
            } else {
                next.kind = .text
                next.indent = min(block.indent + 1, Block.maxIndent)
            }
        }
        blocks.insert(next, at: insertAt)
        return CursorTarget(blockID: next.id, offset: 0)
    }

    /// Backspace was pressed at the very start of a block.
    /// - A styled block (heading, list, quote…) turns into plain text first.
    /// - Indented text moves left one level.
    /// - Otherwise it joins the block above. A divider or page link above is removed instead.
    @discardableResult
    public static func backspaceAtStart(_ blocks: inout [Block], at index: Int) -> CursorTarget? {
        guard blocks.indices.contains(index) else { return nil }
        let block = blocks[index]
        if block.kind != .text && block.kind.hasText {
            blocks[index].turn(into: .text)
            return CursorTarget(blockID: block.id, offset: 0)
        }
        if block.indent > 0 {
            shiftSubtree(&blocks, at: index, by: -1)
            return CursorTarget(blockID: block.id, offset: 0)
        }
        let visible = visibleIndices(blocks)
        guard let position = visible.firstIndex(of: index), position > 0 else { return nil }
        let previousIndex = visible[position - 1]
        let previous = blocks[previousIndex]
        if !previous.kind.hasText {
            blocks.remove(at: previousIndex)
            return CursorTarget(blockID: block.id, offset: 0)
        }
        let joinAt = previous.text.utf16.count
        blocks[previousIndex].text += block.text
        // Children of the removed block keep their place but step up so nothing is orphaned.
        let children = subtree(blocks, at: index).dropFirst()
        for child in children { blocks[child].indent = max(0, blocks[child].indent - 1) }
        blocks.remove(at: index)
        return CursorTarget(blockID: previous.id, offset: joinAt)
    }

    /// Moves a block and its children right (nests it under the block above).
    /// A block can be at most one level deeper than the block above it.
    @discardableResult
    public static func indent(_ blocks: inout [Block], at index: Int) -> Bool {
        guard index > 0, blocks.indices.contains(index) else { return false }
        let limit = min(blocks[index - 1].indent + 1, Block.maxIndent)
        guard blocks[index].indent < limit else { return false }
        shiftSubtree(&blocks, at: index, by: 1)
        return true
    }

    @discardableResult
    public static func outdent(_ blocks: inout [Block], at index: Int) -> Bool {
        guard blocks.indices.contains(index), blocks[index].indent > 0 else { return false }
        shiftSubtree(&blocks, at: index, by: -1)
        return true
    }

    static func shiftSubtree(_ blocks: inout [Block], at index: Int, by delta: Int) {
        for i in subtree(blocks, at: index) {
            blocks[i].indent = max(0, min(Block.maxIndent, blocks[i].indent + delta))
        }
    }

    /// Moves a block (with its children) above the block or group above it. Returns false at the top.
    @discardableResult
    public static func moveUp(_ blocks: inout [Block], at index: Int) -> Bool {
        guard blocks.indices.contains(index), index > 0 else { return false }
        let range = subtree(blocks, at: index)
        let indent = blocks[index].indent
        var target = index - 1
        while target > 0 && blocks[target].indent > indent { target -= 1 }
        let moving = Array(blocks[range])
        blocks.removeSubrange(range)
        blocks.insert(contentsOf: moving, at: target)
        fitIndent(&blocks, at: target)
        return true
    }

    /// Moves a block (with its children) below the next block and its children. Returns false at the end.
    @discardableResult
    public static func moveDown(_ blocks: inout [Block], at index: Int) -> Bool {
        guard blocks.indices.contains(index) else { return false }
        let range = subtree(blocks, at: index)
        guard range.upperBound < blocks.count else { return false }
        let nextRange = subtree(blocks, at: range.upperBound)
        let moving = Array(blocks[range])
        let destination = nextRange.upperBound - moving.count
        blocks.removeSubrange(range)
        blocks.insert(contentsOf: moving, at: destination)
        fitIndent(&blocks, at: destination)
        return true
    }

    /// After a move, keeps the block no more than one level deeper than the one above it.
    static func fitIndent(_ blocks: inout [Block], at index: Int) {
        let limit = index == 0 ? 0 : blocks[index - 1].indent + 1
        let extra = blocks[index].indent - limit
        if extra > 0 { shiftSubtree(&blocks, at: index, by: -extra) }
    }

    /// Deletes a block. Its children step up a level so they stay put.
    @discardableResult
    public static func delete(_ blocks: inout [Block], at index: Int) -> CursorTarget? {
        guard blocks.indices.contains(index) else { return nil }
        for child in subtree(blocks, at: index).dropFirst() {
            blocks[child].indent = max(0, blocks[child].indent - 1)
        }
        blocks.remove(at: index)
        let visible = visibleIndices(blocks)
        if let above = visible.last(where: { $0 < index }) ?? visible.first {
            return CursorTarget(blockID: blocks[above].id, offset: blocks[above].text.utf16.count)
        }
        return nil
    }

    /// Copies a block and its children right below them.
    @discardableResult
    public static func duplicate(_ blocks: inout [Block], at index: Int) -> UUID? {
        guard blocks.indices.contains(index) else { return nil }
        let range = subtree(blocks, at: index)
        let copies = blocks[range].map { block -> Block in
            var b = block
            b.id = UUID()
            return b
        }
        blocks.insert(contentsOf: copies, at: range.upperBound)
        return copies.first?.id
    }

    /// Adds a block of a kind after this one. An empty text block is changed in place instead,
    /// the way picking from the "/" menu on an empty line does.
    @discardableResult
    public static func insert(_ kind: BlockKind, _ blocks: inout [Block], after index: Int?) -> UUID {
        if let index, blocks.indices.contains(index), blocks[index].kind == .text, blocks[index].text.isEmpty {
            blocks[index].turn(into: kind)
            if kind == .divider {
                let after = Block(indent: blocks[index].indent)
                blocks.insert(after, at: index + 1)
                return after.id
            }
            return blocks[index].id
        }
        var block = Block(kind: .text, indent: index.map { blocks.indices.contains($0) ? blocks[$0].indent : 0 } ?? 0)
        block.turn(into: kind)
        let at = index.map { blocks.indices.contains($0) ? subtree(blocks, at: $0).upperBound : blocks.count } ?? blocks.count
        blocks.insert(block, at: at)
        if kind == .divider {
            let after = Block(indent: block.indent)
            blocks.insert(after, at: at + 1)
            return after.id
        }
        return block.id
    }

    /// Opens or closes a toggle.
    public static func toggleCollapsed(_ blocks: inout [Block], id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }), blocks[i].kind == .toggle else { return }
        blocks[i].collapsed.toggle()
    }
}

extension String {
    /// The first `count` UTF-16 units, kept whole at character edges.
    func utf16Prefix(_ count: Int) -> String {
        let index = utf16Index(count)
        return String(self[..<index])
    }

    func utf16Suffix(from count: Int) -> String {
        let index = utf16Index(count)
        return String(self[index...])
    }

    /// The character edge at or just before a UTF-16 offset.
    func utf16Index(_ offset: Int) -> String.Index {
        var used = 0
        var index = startIndex
        while index < endIndex {
            let width = self[index].utf16.count
            if used + width > offset { break }
            used += width
            index = self.index(after: index)
        }
        return index
    }
}
