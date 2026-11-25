import XCTest
@testable import ThoughtsKit

final class WorkspaceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCreateNestsInOrder() {
        var w = Workspace()
        let a = w.createPage(title: "A", now: now)
        let b = w.createPage(title: "B", now: now)
        let child = w.createPage(title: "Child", parentID: a, now: now)
        XCTAssertEqual(w.roots.map(\.id), [a, b])
        XCTAssertEqual(w.children(of: a).map(\.id), [child])
        XCTAssertEqual(w.path(to: child).map(\.title), ["A", "Child"])
        w.reorder([b, a])
        XCTAssertEqual(w.roots.map(\.id), [b, a])
    }

    func testMoveRefusesLoops() {
        var w = Workspace()
        let a = w.createPage(title: "A", now: now)
        let child = w.createPage(title: "Child", parentID: a, now: now)
        XCTAssertFalse(w.move(a, to: child))
        XCTAssertFalse(w.move(a, to: a))
        XCTAssertTrue(w.move(child, to: nil))
        XCTAssertEqual(w.roots.count, 2)
        XCTAssertFalse(w.moveTargets(for: a).contains { $0.id == a })
    }

    func testSubpageLinksFollowMovesAndCopies() {
        var w = Workspace()
        let a = w.createPage(title: "A", now: now)
        let b = w.createPage(title: "B", now: now)
        let child = w.createSubpage(in: a, title: "Child", now: now)
        XCTAssertEqual(w[a]?.blocks.map(\.linkedPageID), [child])
        let copy = w.duplicate(child, now: now)!
        XCTAssertEqual(w[a]?.blocks.map(\.linkedPageID), [child, copy])
        XCTAssertTrue(w.move(child, to: b, now: now))
        XCTAssertEqual(w[a]?.blocks.map(\.linkedPageID), [copy])
        XCTAssertEqual(w[b]?.blocks.map(\.linkedPageID), [child])
        let db = w.createSubpage(in: nil, kind: .database, now: now)
        let row = w.createSubpage(in: db, now: now)
        XCTAssertTrue(w[db]?.blocks.isEmpty ?? false, "Databases don't get link blocks")
        XCTAssertTrue(w.isRow(row))
    }

    func testTrashRestoreAndDeleteForever() {
        var w = Workspace()
        let a = w.createPage(title: "A", now: now)
        let child = w.createPage(title: "Child", parentID: a, now: now)
        let other = w.createPage(title: "Other", blocks: [Block(kind: .pageLink, linkedPageID: child)], now: now)
        w.toggleFavorite(child, now: now)

        w.trash(a, now: now)
        XCTAssertTrue(w.isInTrash(child))
        XCTAssertEqual(w.roots.map(\.id), [other])
        XCTAssertTrue(w.favorites.isEmpty, "Favorites inside the Trash are hidden")
        XCTAssertEqual(w.trashed.map(\.id), [a])
        XCTAssertTrue(w.search("child").isEmpty)

        w.restore(a)
        XCTAssertFalse(w.isInTrash(child))
        XCTAssertEqual(w.favorites.map(\.id), [child])

        w.trash(a, now: now)
        w.emptyTrash()
        XCTAssertNil(w[a])
        XCTAssertNil(w[child])
        XCTAssertTrue(w[other]?.blocks.isEmpty ?? false, "Links to deleted pages go too")
    }

    func testRestoreChildOfTrashedPageGoesToTop() {
        var w = Workspace()
        let a = w.createPage(title: "A", now: now)
        let child = w.createPage(title: "Child", parentID: a, now: now)
        w.trash(child, now: now)
        w.trash(a, now: now)
        w.restore(child)
        XCTAssertNil(w[child]?.parentID)
        XCTAssertFalse(w.isInTrash(child))
    }

    func testDuplicateCopiesSubpagesAndRelinks() {
        var w = Workspace()
        let a = w.createPage(title: "A", now: now)
        let child = w.createPage(title: "Child", parentID: a, now: now)
        w[a]?.blocks = [Block(kind: .pageLink, linkedPageID: child), Block(text: "hi")]
        let b = w.createPage(title: "B", now: now)
        let copy = w.duplicate(a, now: now)!
        XCTAssertEqual(w.roots.map(\.id), [a, copy, b])
        let copiedChild = w.children(of: copy)
        XCTAssertEqual(copiedChild.map(\.title), ["Child"])
        XCTAssertNotEqual(copiedChild.first?.id, child)
        XCTAssertEqual(w[copy]?.blocks.first?.linkedPageID, copiedChild.first?.id)
    }

    func testRecentsAndFavorites() {
        var w = Workspace()
        let a = w.createPage(title: "A", now: now)
        let b = w.createPage(title: "B", now: now)
        w.markOpened(a, now: now)
        w.markOpened(b, now: now.addingTimeInterval(10))
        XCTAssertEqual(w.recents().map(\.id), [b, a])
        w.toggleFavorite(b, now: now)
        w.toggleFavorite(a, now: now.addingTimeInterval(1))
        XCTAssertEqual(w.favorites.map(\.id), [b, a])
        w.toggleFavorite(b, now: now)
        XCTAssertEqual(w.favorites.map(\.id), [a])
    }

    func testSearchRanksTitlesFirstAndIgnoresAccents() {
        var w = Workspace()
        let body = w.createPage(title: "Notes", blocks: [Block(text: "Ideas for the café menu and more")], now: now)
        let title = w.createPage(title: "Cafe plans", now: now)
        let results = w.search("cafe")
        XCTAssertEqual(results.map(\.pageID), [title, body])
        XCTAssertTrue(results[0].inTitle)
        XCTAssertEqual(results[1].snippet, "Ideas for the café menu and more")
        XCTAssertEqual(w.search("menu ideas").map(\.pageID), [body], "Every word must match")
        XCTAssertTrue(w.search("  ").isEmpty)
    }

    func testSaveAndLoadRoundTrip() throws {
        let w = Workspace.sample(now: now)
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(Workspace.self, from: data)
        XCTAssertEqual(back, w)
    }

    func testOldOrPartialFilesStillLoad() throws {
        let json = #"{"pages":[{"id":"8C3E4D4B-5E35-4B8C-9C59-1B7F0C3B2A10","title":"Old","blocks":[{"text":"hi","kind":"mystery"}],"parentID":"00000000-0000-0000-0000-000000000001"}]}"#
        let w = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))
        XCTAssertEqual(w.roots.map(\.title), ["Old"], "A missing parent moves the page to the top")
        XCTAssertEqual(w.roots.first?.blocks.first?.kind, .text, "Unknown block kinds load as text")
    }

    func testSampleIsSound() {
        let w = Workspace.sample(now: now)
        XCTAssertFalse(w.roots.isEmpty)
        XCTAssertEqual(w.favorites.count, 2)
        XCTAssertGreaterThan(w.recents().count, 3)
        for page in w.pages.values {
            for block in page.blocks where block.kind == .pageLink {
                XCTAssertNotNil(block.linkedPageID.flatMap { w[$0] })
            }
        }
    }

    func testTemplatesAllBuild() {
        var w = Workspace()
        for template in Templates.all {
            let id = Templates.add(template.id, to: &w, now: now)
            XCTAssertNotNil(id, template.id)
            XCTAssertEqual(w[id!]?.title, template.title)
        }
    }

    func testMarkdownExport() {
        var w = Workspace()
        let id = w.createPage(title: "List", icon: "🛒", blocks: [
            Block(kind: .heading1, text: "Food"),
            Block(kind: .numbered, text: "Eggs"),
            Block(kind: .numbered, text: "Milk"),
            Block(kind: .todo, text: "Bread", indent: 1, checked: true),
            Block(kind: .divider),
        ], now: now)
        XCTAssertEqual(MarkdownExport.markdown(for: id, in: w),
                       "# 🛒 List\n\n## Food\n1. Eggs\n2. Milk\n  - [x] Bread\n---\n")
    }
}

final class DatabaseTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeProjects() -> (Workspace, UUID, DatabaseSchema) {
        var w = Workspace()
        let id = Templates.projects(in: &w, parentID: nil, rows: [
            ("Paint", 1, 1, 6),
            ("Trip", 0, 2, 21),
            ("Garage", 0, 0, nil),
            ("Tires", 2, 1, -2),
        ], now: now)
        return (w, id, w[id]!.database!)
    }

    func testBoardColumnsGroupByStatus() {
        let (w, id, _) = makeProjects()
        let columns = w.boardColumns(of: id)
        XCTAssertEqual(columns.map(\.title), ["No Status", "Not started", "In progress", "Done"])
        XCTAssertEqual(columns.map { $0.rows.map(\.title) }, [[], ["Trip", "Garage"], ["Paint"], ["Tires"]])
    }

    func testMoveRowBetweenColumns() {
        var (w, id, schema) = makeProjects()
        let garage = w.children(of: id).first { $0.title == "Garage" }!.id
        let paint = w.children(of: id).first { $0.title == "Paint" }!.id
        let done = schema.groupProperty!.options[2].id
        w.moveRow(garage, toOption: done, before: nil)
        XCTAssertEqual(w.boardColumns(of: id)[3].rows.map(\.title), ["Garage", "Tires"])
        let inProgress = schema.groupProperty!.options[1].id
        w.moveRow(garage, toOption: inProgress, before: paint)
        XCTAssertEqual(w.boardColumns(of: id)[2].rows.map(\.title), ["Garage", "Paint"])
        w.moveRow(garage, toOption: nil)
        XCTAssertEqual(w.boardColumns(of: id)[0].rows.map(\.title), ["Garage"])
    }

    func testSortByPropertyPutsEmptyLast() {
        var (w, id, schema) = makeProjects()
        let due = schema.properties[2].id
        w[id]?.database?.sort = DatabaseSort(key: .property(due), ascending: true)
        XCTAssertEqual(w.rows(of: id).map(\.title), ["Tires", "Paint", "Trip", "Garage"])
        w[id]?.database?.sort.ascending = false
        XCTAssertEqual(w.rows(of: id).map(\.title), ["Trip", "Paint", "Tires", "Garage"])
        w[id]?.database?.sort = DatabaseSort(key: .property(schema.properties[1].id), ascending: false)
        XCTAssertEqual(w.rows(of: id).map(\.title), ["Trip", "Paint", "Tires", "Garage"], "High, then Medium in manual order, then Low")
        w[id]?.database?.sort = DatabaseSort(key: .title)
        XCTAssertEqual(w.rows(of: id).map(\.title), ["Garage", "Paint", "Tires", "Trip"])
    }

    func testFilterBySelect() {
        var (w, id, schema) = makeProjects()
        let status = schema.properties[0]
        w[id]?.database?.filter = DatabaseFilter(propertyID: status.id, optionIDs: [status.options[0].id, status.options[2].id])
        XCTAssertEqual(w.rows(of: id).map(\.title), ["Trip", "Garage", "Tires"])
    }

    func testChangeTextColumnToSelectMakesOptions() {
        var w = Workspace()
        let id = Templates.reading(in: &w, parentID: nil, rows: [
            ("A", "Ann", 0, 0), ("B", "Bob", 0, 0), ("C", "ann", 0, 0),
        ], now: now)
        let author = w[id]!.database!.properties[0].id
        w.changePropertyType(author, in: id, to: .select)
        let property = w[id]!.database!.property(author)!
        XCTAssertEqual(property.type, .select)
        XCTAssertEqual(property.options.map(\.name), ["Ann", "Bob"])
        let rows = w.children(of: id)
        XCTAssertEqual(rows[0].value(author), rows[2].value(author), "Same name, any case, same option")
        w.changePropertyType(author, in: id, to: .text)
        XCTAssertEqual(w.children(of: id)[1].value(author), .text("Bob"))
    }

    func testDeletePropertyAndOptionClearValues() {
        var (w, id, schema) = makeProjects()
        let status = schema.properties[0]
        w.deleteOption(status.options[0].id, of: status.id, in: id)
        XCTAssertEqual(w.boardColumns(of: id)[0].rows.map(\.title), ["Trip", "Garage"])
        w.deleteProperty(schema.properties[1].id, in: id)
        XCTAssertEqual(w[id]?.database?.properties.count, 2)
        XCTAssertTrue(w.children(of: id).allSatisfy { $0.value(schema.properties[1].id) == nil })
    }

    func testRowsAreRecognised() {
        let (w, id, _) = makeProjects()
        let row = w.children(of: id)[0].id
        XCTAssertTrue(w.isRow(row))
        XCTAssertEqual(w.database(of: row)?.id, id)
        XCTAssertFalse(w.isRow(id))
    }
}
