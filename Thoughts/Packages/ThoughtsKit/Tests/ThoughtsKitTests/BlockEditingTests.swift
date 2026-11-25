import XCTest
@testable import ThoughtsKit

final class BlockEditingTests: XCTestCase {
    func testReturnSplitsTextAtCursor() {
        var blocks = [Block(kind: .heading1, text: "Hello world")]
        let target = BlockEditing.pressReturn(&blocks, at: 0, offset: 5)
        XCTAssertEqual(blocks.map(\.text), ["Hello", " world"])
        XCTAssertEqual(blocks[1].kind, .text, "A heading continues as text")
        XCTAssertEqual(target, CursorTarget(blockID: blocks[1].id, offset: 0))
    }

    func testReturnContinuesLists() {
        var blocks = [Block(kind: .todo, text: "Milk", indent: 1, checked: true)]
        BlockEditing.pressReturn(&blocks, at: 0, offset: 4)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].kind, .todo)
        XCTAssertEqual(blocks[1].indent, 1)
        XCTAssertFalse(blocks[1].checked)
    }

    func testReturnOnEmptyListItemStepsOut() {
        var blocks = [Block(kind: .bulleted, text: "", indent: 1)]
        BlockEditing.pressReturn(&blocks, at: 0, offset: 0)
        XCTAssertEqual(blocks[0].indent, 0)
        XCTAssertEqual(blocks[0].kind, .bulleted)
        BlockEditing.pressReturn(&blocks, at: 0, offset: 0)
        XCTAssertEqual(blocks[0].kind, .text)
        XCTAssertEqual(blocks.count, 1)
    }

    func testReturnAtStartInsertsAbove() {
        var blocks = [Block(kind: .heading2, text: "Title")]
        let id = blocks[0].id
        let target = BlockEditing.pressReturn(&blocks, at: 0, offset: 0)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].text, "")
        XCTAssertEqual(blocks[0].kind, .text)
        XCTAssertEqual(blocks[1].id, id)
        XCTAssertEqual(target?.blockID, id)
    }

    func testReturnInOpenToggleNestsInside() {
        var blocks = [Block(kind: .toggle, text: "More")]
        BlockEditing.pressReturn(&blocks, at: 0, offset: 4)
        XCTAssertEqual(blocks[1].kind, .text)
        XCTAssertEqual(blocks[1].indent, 1)
    }

    func testReturnInClosedToggleGoesAfterItsChildren() {
        var blocks = [Block(kind: .toggle, text: "More", collapsed: true), Block(text: "hidden", indent: 1)]
        BlockEditing.pressReturn(&blocks, at: 0, offset: 4)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[2].kind, .toggle)
        XCTAssertEqual(blocks[2].indent, 0)
    }

    func testReturnKeepsEmojiWhole() {
        var blocks = [Block(text: "a👍b")]
        // UTF-16: a=1, 👍=2, b=1. An offset in the middle of the emoji rounds down.
        BlockEditing.pressReturn(&blocks, at: 0, offset: 2)
        XCTAssertEqual(blocks.map(\.text), ["a", "👍b"])
    }

    func testBackspaceTurnsStyledBlockIntoText() {
        var blocks = [Block(text: "x"), Block(kind: .quote, text: "Q")]
        BlockEditing.backspaceAtStart(&blocks, at: 1)
        XCTAssertEqual(blocks[1].kind, .text)
        XCTAssertEqual(blocks.count, 2)
    }

    func testBackspaceOutdentsThenMerges() {
        var blocks = [Block(text: "Hello"), Block(text: " there", indent: 1)]
        BlockEditing.backspaceAtStart(&blocks, at: 1)
        XCTAssertEqual(blocks[1].indent, 0)
        let target = BlockEditing.backspaceAtStart(&blocks, at: 1)
        XCTAssertEqual(blocks.map(\.text), ["Hello there"])
        XCTAssertEqual(target, CursorTarget(blockID: blocks[0].id, offset: 5))
    }

    func testBackspaceRemovesDividerAbove() {
        var blocks = [Block(text: "a"), Block(kind: .divider), Block(text: "b")]
        BlockEditing.backspaceAtStart(&blocks, at: 2)
        XCTAssertEqual(blocks.map(\.kind), [.text, .text])
        XCTAssertEqual(blocks.map(\.text), ["a", "b"])
    }

    func testBackspaceSkipsHiddenToggleChildren() {
        var blocks = [Block(kind: .toggle, text: "T", collapsed: true), Block(text: "in", indent: 1), Block(text: "out")]
        BlockEditing.backspaceAtStart(&blocks, at: 2)
        XCTAssertEqual(blocks[0].text, "Tout")
        XCTAssertEqual(blocks.count, 2)
    }

    func testBackspaceOnFirstPlainBlockDoesNothing() {
        var blocks = [Block(text: "a")]
        XCTAssertNil(BlockEditing.backspaceAtStart(&blocks, at: 0))
    }

    func testIndentLimitAndChildrenMoveTogether() {
        var blocks = [Block(text: "a"), Block(text: "b"), Block(text: "c", indent: 1)]
        XCTAssertFalse(BlockEditing.indent(&blocks, at: 0), "The first block can't nest")
        XCTAssertTrue(BlockEditing.indent(&blocks, at: 1))
        XCTAssertEqual(blocks.map(\.indent), [0, 1, 2])
        XCTAssertFalse(BlockEditing.indent(&blocks, at: 1), "Only one level deeper than the block above")
        XCTAssertTrue(BlockEditing.outdent(&blocks, at: 1))
        XCTAssertEqual(blocks.map(\.indent), [0, 0, 1])
    }

    func testNumbering() {
        let blocks = [
            Block(kind: .numbered, text: "one"),
            Block(kind: .numbered, text: "two"),
            Block(kind: .numbered, text: "two-a", indent: 1),
            Block(kind: .numbered, text: "two-b", indent: 1),
            Block(kind: .numbered, text: "three"),
            Block(text: "break"),
            Block(kind: .numbered, text: "one again"),
        ]
        XCTAssertEqual([0, 1, 2, 3, 4, 6].map { BlockEditing.number(blocks, at: $0) }, [1, 2, 1, 2, 3, 1])
    }

    func testVisibleIndicesHideClosedToggles() {
        let blocks = [
            Block(kind: .toggle, text: "t", collapsed: true),
            Block(text: "a", indent: 1),
            Block(text: "b", indent: 2),
            Block(text: "c"),
        ]
        XCTAssertEqual(BlockEditing.visibleIndices(blocks), [0, 3])
    }

    func testMoveUpAndDownCarryChildren() {
        var blocks = [Block(text: "A"), Block(text: "B"), Block(text: "B1", indent: 1), Block(text: "C")]
        XCTAssertTrue(BlockEditing.moveUp(&blocks, at: 1))
        XCTAssertEqual(blocks.map(\.text), ["B", "B1", "A", "C"])
        XCTAssertTrue(BlockEditing.moveDown(&blocks, at: 0))
        XCTAssertEqual(blocks.map(\.text), ["A", "B", "B1", "C"])
        XCTAssertTrue(BlockEditing.moveDown(&blocks, at: 1))
        XCTAssertEqual(blocks.map(\.text), ["A", "C", "B", "B1"])
        XCTAssertFalse(BlockEditing.moveDown(&blocks, at: 2))
        XCTAssertFalse(BlockEditing.moveUp(&blocks, at: 0))
    }

    func testMoveUpToTopRemovesIndent() {
        var blocks = [Block(text: "A"), Block(text: "A1", indent: 1)]
        BlockEditing.moveUp(&blocks, at: 1)
        XCTAssertEqual(blocks.map(\.text), ["A1", "A"])
        XCTAssertEqual(blocks[0].indent, 0)
    }

    func testInsertReplacesEmptyTextBlock() {
        var blocks = [Block(text: "")]
        let id = BlockEditing.insert(.todo, &blocks, after: 0)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].kind, .todo)
        XCTAssertEqual(id, blocks[0].id)
        let divider = BlockEditing.insert(.divider, &blocks, after: 0)
        XCTAssertEqual(blocks.map(\.kind), [.todo, .divider, .text], "A line to keep typing on goes after a divider")
        XCTAssertEqual(divider, blocks[2].id)
    }

    func testDeleteKeepsChildren() {
        var blocks = [Block(text: "A"), Block(text: "B"), Block(text: "B1", indent: 1)]
        let target = BlockEditing.delete(&blocks, at: 1)
        XCTAssertEqual(blocks.map(\.text), ["A", "B1"])
        XCTAssertEqual(blocks[1].indent, 0)
        XCTAssertEqual(target, CursorTarget(blockID: blocks[0].id, offset: 1))
    }

    func testDuplicateCopiesSubtree() {
        var blocks = [Block(text: "A"), Block(text: "A1", indent: 1), Block(text: "B")]
        BlockEditing.duplicate(&blocks, at: 0)
        XCTAssertEqual(blocks.map(\.text), ["A", "A1", "A", "A1", "B"])
        XCTAssertEqual(Set(blocks.map(\.id)).count, 5)
    }
}

final class ShortcutTests: XCTestCase {
    func testShortcuts() {
        XCTAssertEqual(MarkdownShortcut.match("# Hi")?.kind, .heading1)
        XCTAssertEqual(MarkdownShortcut.match("## ")?.kind, .heading2)
        XCTAssertEqual(MarkdownShortcut.match("### x")?.rest, "x")
        XCTAssertEqual(MarkdownShortcut.match("- item")?.kind, .bulleted)
        XCTAssertEqual(MarkdownShortcut.match("12. item")?.kind, .numbered)
        XCTAssertEqual(MarkdownShortcut.match("1) item")?.rest, "item")
        XCTAssertEqual(MarkdownShortcut.match("[] task")?.kind, .todo)
        XCTAssertEqual(MarkdownShortcut.match("[x] done")?.checked, true)
        XCTAssertEqual(MarkdownShortcut.match("> more")?.kind, .toggle)
        XCTAssertEqual(MarkdownShortcut.match("\" said")?.kind, .quote)
        XCTAssertEqual(MarkdownShortcut.match("---")?.kind, .divider)
        XCTAssertEqual(MarkdownShortcut.match("```")?.kind, .code)
        XCTAssertNil(MarkdownShortcut.match("#hashtag"))
        XCTAssertNil(MarkdownShortcut.match("a. b"))
        XCTAssertNil(MarkdownShortcut.match("2025 was"))
        XCTAssertNil(MarkdownShortcut.match("# Hi", in: .bulleted), "Only plain text converts")
    }

    func testSlashQuery() {
        XCTAssertEqual(SlashCommands.activeQuery(in: "/")?.query, "")
        XCTAssertEqual(SlashCommands.activeQuery(in: "/tod")?.query, "tod")
        XCTAssertEqual(SlashCommands.activeQuery(in: "Buy milk /h1")?.query, "h1")
        XCTAssertEqual(SlashCommands.activeQuery(in: "Buy milk /h1")?.slashOffset, 9)
        XCTAssertNil(SlashCommands.activeQuery(in: "and/or"))
        XCTAssertNil(SlashCommands.activeQuery(in: "/ "))
        XCTAssertEqual(SlashCommands.removingQuery(from: "Buy milk /to"), "Buy milk ")
    }

    func testSlashFilterRanksTitleStartsFirst() {
        XCTAssertEqual(SlashCommands.filter("").count, SlashCommands.all.count)
        XCTAssertEqual(SlashCommands.filter("to").first?.action, .turnInto(.todo))
        XCTAssertEqual(SlashCommands.filter("h2").first?.action, .turnInto(.heading2))
        XCTAssertEqual(SlashCommands.filter("board").first?.action, .newDatabase)
        XCTAssertEqual(SlashCommands.filter("head").map(\.action),
                       [.turnInto(.heading1), .turnInto(.heading2), .turnInto(.heading3)])
        XCTAssertTrue(SlashCommands.filter("zzz").isEmpty)
    }
}
