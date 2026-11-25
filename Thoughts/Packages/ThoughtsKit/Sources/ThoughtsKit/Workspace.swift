import Foundation

/// Every page, keyed by ID. Saved as JSON with the pages as an array.
public struct Workspace: Codable, Equatable, Sendable {
    public var pages: [UUID: Page]

    public init(pages: [Page] = []) {
        self.pages = Dictionary(pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private enum CodingKeys: String, CodingKey {
        case version, pages
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decodeIfPresent([Page].self, forKey: .pages) ?? []
        self.init(pages: list)
        repair()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .version)
        try c.encode(pages.values.sorted { $0.created < $1.created }, forKey: .pages)
    }

    public subscript(id: UUID) -> Page? {
        get { pages[id] }
        set { pages[id] = newValue }
    }

    /// Moves pages whose parent no longer exists to the top level, and breaks any parent loop.
    public mutating func repair() {
        for id in Array(pages.keys) {
            guard let parent = pages[id]?.parentID else { continue }
            if pages[parent] == nil || isAncestor(id, of: parent) {
                pages[id]?.parentID = nil
            }
        }
    }

    // MARK: - Tree

    /// Children in order, leaving out pages in the Trash unless asked.
    public func children(of parentID: UUID?, includeTrashed: Bool = false) -> [Page] {
        pages.values
            .filter { $0.parentID == parentID && (includeTrashed || $0.trashed == nil) }
            .sorted(by: Workspace.siblingOrder)
    }

    static func siblingOrder(_ a: Page, _ b: Page) -> Bool {
        if a.order != b.order { return a.order < b.order }
        if a.created != b.created { return a.created < b.created }
        return a.id.uuidString < b.id.uuidString
    }

    /// Top-level pages not in the Trash.
    public var roots: [Page] {
        children(of: nil)
    }

    /// True if `ancestor` is `id` itself or any page above it.
    public func isAncestor(_ ancestor: UUID, of id: UUID) -> Bool {
        var current: UUID? = id
        var seen = Set<UUID>()
        while let c = current, !seen.contains(c) {
            if c == ancestor { return true }
            seen.insert(c)
            current = pages[c]?.parentID
        }
        return false
    }

    /// Every page below this one, at any depth, Trash included.
    public func descendants(of id: UUID) -> [UUID] {
        var result: [UUID] = []
        var queue = [id]
        var seen: Set<UUID> = [id]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            for child in pages.values where child.parentID == next && !seen.contains(child.id) {
                seen.insert(child.id)
                result.append(child.id)
                queue.append(child.id)
            }
        }
        return result
    }

    /// The pages from the top level down to this one, this one last.
    public func path(to id: UUID) -> [Page] {
        var result: [Page] = []
        var current: UUID? = id
        var seen = Set<UUID>()
        while let c = current, let page = pages[c], !seen.contains(c) {
            seen.insert(c)
            result.insert(page, at: 0)
            current = page.parentID
        }
        return result
    }

    /// True if the page or any page above it is in the Trash.
    public func isInTrash(_ id: UUID) -> Bool {
        path(to: id).contains { $0.trashed != nil }
    }

    /// True if this page is a row of a database.
    public func isRow(_ id: UUID) -> Bool {
        guard let parent = pages[id]?.parentID else { return false }
        return pages[parent]?.kind == .database
    }

    /// The database this page is a row of.
    public func database(of rowID: UUID) -> Page? {
        guard let parent = pages[rowID]?.parentID, let db = pages[parent], db.kind == .database else { return nil }
        return db
    }

    private func nextOrder(under parentID: UUID?) -> Double {
        (children(of: parentID, includeTrashed: true).map(\.order).max() ?? 0) + 1
    }

    // MARK: - Making pages

    /// Adds an empty page at the end of its parent's pages and returns its ID.
    @discardableResult
    public mutating func createPage(title: String = "", icon: String? = nil, parentID: UUID? = nil,
                                    kind: PageKind = .document, blocks: [Block] = [], now: Date = Date()) -> UUID {
        let page = Page(kind: kind, title: title, icon: icon, parentID: parentID,
                        order: nextOrder(under: parentID), blocks: blocks, created: now)
        pages[page.id] = page
        if let parentID { touch(parentID, now: now) }
        return page.id
    }

    /// Adds a page inside another page, the way "+" on a page does: when the parent is a
    /// document, a link to the new page goes at the end of its writing.
    @discardableResult
    public mutating func createSubpage(in parentID: UUID?, title: String = "", kind: PageKind = .document,
                                       addLink: Bool = true, now: Date = Date()) -> UUID {
        let id = createPage(title: title, parentID: parentID, kind: kind, now: now)
        if addLink, let parentID, pages[parentID]?.kind == .document {
            pages[parentID]?.blocks.append(Block(kind: .pageLink, linkedPageID: id))
        }
        return id
    }

    /// Adds a row to a database, with starting values.
    @discardableResult
    public mutating func addRow(to databaseID: UUID, title: String = "", values: [UUID: PropertyValue] = [:],
                                now: Date = Date()) -> UUID {
        let id = createPage(title: title, parentID: databaseID, now: now)
        for (key, value) in values { pages[id]?.setValue(value, for: key) }
        return id
    }

    /// Marks a page as just edited.
    public mutating func touch(_ id: UUID, now: Date = Date()) {
        pages[id]?.edited = now
    }

    public mutating func markOpened(_ id: UUID, now: Date = Date()) {
        pages[id]?.opened = now
    }

    public mutating func toggleFavorite(_ id: UUID, now: Date = Date()) {
        guard pages[id] != nil else { return }
        let wasFavorite = pages[id]?.favorited != nil
        pages[id]?.favorited = wasFavorite ? nil : now
    }

    // MARK: - Moving

    /// Where a page could be moved: the top level (nil) or any document page that isn't
    /// itself, below itself, already its parent, or in the Trash.
    public func moveTargets(for id: UUID) -> [Page] {
        let current = pages[id]?.parentID
        return pages.values
            .filter { $0.kind == .document && $0.id != current && !isAncestor(id, of: $0.id) && !isInTrash($0.id) }
            .sorted { path(to: $0.id).map(\.displayTitle).joined(separator: "/")
                .localizedCaseInsensitiveCompare(path(to: $1.id).map(\.displayTitle).joined(separator: "/")) == .orderedAscending }
    }

    /// Moves a page (and everything under it) into another page, or to the top level.
    /// Returns false if that would put the page inside itself.
    @discardableResult
    public mutating func move(_ id: UUID, to newParent: UUID?, now: Date = Date()) -> Bool {
        guard pages[id] != nil else { return false }
        if let newParent {
            guard pages[newParent] != nil, !isAncestor(id, of: newParent) else { return false }
        }
        let oldParent = pages[id]?.parentID
        guard oldParent != newParent else { return true }
        let order = nextOrder(under: newParent)
        pages[id]?.parentID = newParent
        pages[id]?.order = order
        // The link moves with the page: out of the old parent's writing, onto the end of the new one's.
        if let oldParent {
            pages[oldParent]?.blocks.removeAll { $0.kind == .pageLink && $0.linkedPageID == id }
        }
        if let newParent, pages[newParent]?.kind == .document {
            pages[newParent]?.blocks.append(Block(kind: .pageLink, linkedPageID: id))
        }
        touch(id, now: now)
        return true
    }

    /// Puts siblings in the given order (from a drag in a list). IDs not listed keep their place after these.
    public mutating func reorder(_ ids: [UUID]) {
        for (index, id) in ids.enumerated() {
            pages[id]?.order = Double(index + 1)
        }
    }

    // MARK: - Trash

    /// Puts a page and everything under it in the Trash.
    public mutating func trash(_ id: UUID, now: Date = Date()) {
        pages[id]?.trashed = now
    }

    /// Takes a page out of the Trash. If the page it was in is gone or still in the Trash,
    /// it comes back at the top level.
    public mutating func restore(_ id: UUID) {
        guard pages[id] != nil else { return }
        pages[id]?.trashed = nil
        if let parent = pages[id]?.parentID, pages[parent] == nil || isInTrash(parent) {
            let order = nextOrder(under: nil)
            pages[id]?.parentID = nil
            pages[id]?.order = order
        }
    }

    /// Pages put in the Trash, newest first. Subpages that went in with them aren't listed.
    public var trashed: [Page] {
        pages.values.filter { $0.trashed != nil }.sorted { ($0.trashed ?? .distantPast) > ($1.trashed ?? .distantPast) }
    }

    /// Deletes a page and everything under it for good, and removes links to them.
    public mutating func deleteForever(_ id: UUID) {
        let gone = Set([id] + descendants(of: id))
        for g in gone { pages[g] = nil }
        func isGone(_ link: UUID?) -> Bool {
            guard let link else { return false }
            return gone.contains(link)
        }
        for key in Array(pages.keys) {
            guard let blocks = pages[key]?.blocks,
                  blocks.contains(where: { $0.kind == .pageLink && isGone($0.linkedPageID) }) else { continue }
            pages[key]?.blocks = blocks.filter { !($0.kind == .pageLink && isGone($0.linkedPageID)) }
        }
    }

    public mutating func emptyTrash() {
        for page in trashed { deleteForever(page.id) }
    }

    // MARK: - Duplicating

    /// Copies a page and everything under it, right after the original. Links between the
    /// copied pages point at the copies. Returns the new page's ID.
    @discardableResult
    public mutating func duplicate(_ id: UUID, now: Date = Date()) -> UUID? {
        guard let original = pages[id] else { return nil }
        let all = [id] + descendants(of: id)
        var newIDs: [UUID: UUID] = [:]
        for old in all { newIDs[old] = UUID() }
        for old in all {
            guard var copy = pages[old], let newID = newIDs[old] else { continue }
            copy.id = newID
            if old == id {
                copy.order = original.order + 0.5
                copy.favorited = nil
            } else if let parent = copy.parentID {
                copy.parentID = newIDs[parent] ?? parent
            }
            copy.created = now
            copy.edited = now
            copy.opened = nil
            copy.trashed = nil
            copy.blocks = copy.blocks.map { block in
                var b = block
                b.id = UUID()
                if let link = b.linkedPageID, let mapped = newIDs[link] { b.linkedPageID = mapped }
                return b
            }
            pages[newID] = copy
        }
        let siblings = children(of: original.parentID).map(\.id)
        reorder(siblings)
        // A link to the original in its parent gets a link to the copy right after it.
        if let parent = original.parentID, let copy = newIDs[id], var blocks = pages[parent]?.blocks,
           let at = blocks.firstIndex(where: { $0.kind == .pageLink && $0.linkedPageID == id }) {
            blocks.insert(Block(kind: .pageLink, indent: blocks[at].indent, linkedPageID: copy), at: at + 1)
            pages[parent]?.blocks = blocks
        }
        return newIDs[id]
    }

    // MARK: - Lists for the home screen

    public var favorites: [Page] {
        pages.values.filter { $0.favorited != nil && !isInTrash($0.id) }
            .sorted { ($0.favorited ?? .distantPast) < ($1.favorited ?? .distantPast) }
    }

    /// Recently opened pages, newest first. Database rows are included.
    public func recents(limit: Int = 8) -> [Page] {
        Array(pages.values.filter { $0.opened != nil && !isInTrash($0.id) }
            .sorted { ($0.opened ?? .distantPast) > ($1.opened ?? .distantPast) }
            .prefix(limit))
    }

    // MARK: - Database rows

    /// A database's rows, filtered and sorted by its view settings.
    public func rows(of databaseID: UUID) -> [Page] {
        guard let db = pages[databaseID], let schema = db.database else { return [] }
        var rows = children(of: databaseID)
        if let filter = schema.filter, let property = schema.property(filter.propertyID) {
            rows = rows.filter { Workspace.matches($0, filter: filter, property: property) }
        }
        return Workspace.sorted(rows, by: schema.sort, schema: schema)
    }

    static func matches(_ row: Page, filter: DatabaseFilter, property: PropertyDefinition) -> Bool {
        let value = row.value(property.id)
        switch property.type {
        case .checkbox:
            guard let want = filter.checked else { return true }
            if case .checkbox(let on) = value { return on == want }
            return want == false
        case .select, .multiSelect:
            if filter.optionIDs.isEmpty { return true }
            let have = value?.optionIDs ?? []
            return have.contains { filter.optionIDs.contains($0) }
        default:
            return true
        }
    }

    /// Sorts rows. Rows with no value for the sort property go last either way.
    public static func sorted(_ rows: [Page], by sort: DatabaseSort, schema: DatabaseSchema) -> [Page] {
        let manual = rows.sorted(by: siblingOrder)
        func compare(_ a: Page, _ b: Page) -> ComparisonResult {
            switch sort.key {
            case .manual: return .orderedSame
            case .title: return a.displayTitle.localizedStandardCompare(b.displayTitle)
            case .created: return a.created == b.created ? .orderedSame : (a.created < b.created ? .orderedAscending : .orderedDescending)
            case .edited: return a.edited == b.edited ? .orderedSame : (a.edited < b.edited ? .orderedAscending : .orderedDescending)
            case .property(let id):
                guard let property = schema.property(id) else { return .orderedSame }
                return compareValues(a.value(id), b.value(id), property: property)
            }
        }
        guard sort.key != .manual else { return manual }
        // Stable: ties keep the manual order.
        let indexed = Array(manual.enumerated())
        return indexed.sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            if case .property(let id) = sort.key {
                let aEmpty = a.value(id) == nil, bEmpty = b.value(id) == nil
                if aEmpty != bEmpty { return bEmpty }
            }
            let result = compare(a, b)
            if result == .orderedSame { return lhs.offset < rhs.offset }
            return sort.ascending ? result == .orderedAscending : result == .orderedDescending
        }.map(\.element)
    }

    static func compareValues(_ a: PropertyValue?, _ b: PropertyValue?, property: PropertyDefinition) -> ComparisonResult {
        func optionIndex(_ id: UUID?) -> Int {
            guard let id else { return Int.max }
            return property.options.firstIndex { $0.id == id } ?? Int.max
        }
        func ordered<T: Comparable>(_ x: T, _ y: T) -> ComparisonResult {
            x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
        }
        switch (a, b) {
        case (.text(let x)?, .text(let y)?), (.url(let x)?, .url(let y)?):
            return x.localizedStandardCompare(y)
        case (.number(let x)?, .number(let y)?): return ordered(x, y)
        case (.date(let x)?, .date(let y)?): return ordered(x, y)
        case (.checkbox(let x)?, .checkbox(let y)?): return ordered(x ? 1 : 0, y ? 1 : 0)
        case (.select(let x)?, .select(let y)?): return ordered(optionIndex(x), optionIndex(y))
        case (.multiSelect(let x)?, .multiSelect(let y)?): return ordered(optionIndex(x.first), optionIndex(y.first))
        default: return .orderedSame
        }
    }

    /// The board's columns: one per option of the group property, then "No <property>" for the rest.
    public func boardColumns(of databaseID: UUID) -> [BoardColumn] {
        guard let schema = pages[databaseID]?.database else { return [] }
        let all = rows(of: databaseID)
        guard let group = schema.groupProperty else {
            return [BoardColumn(option: nil, title: "All", rows: all)]
        }
        var columns: [BoardColumn] = []
        let known = Set(group.options.map(\.id))
        let loose = all.filter { row in row.value(group.id)?.selectID.map { !known.contains($0) } ?? true }
        columns.append(BoardColumn(option: nil, title: "No \(group.name)", rows: loose))
        for option in group.options {
            columns.append(BoardColumn(option: option, title: option.name,
                                       rows: all.filter { $0.value(group.id)?.selectID == option.id }))
        }
        return columns
    }

    /// Moves a row to a board column (sets its group property), placing it before `before` if given.
    public mutating func moveRow(_ rowID: UUID, toOption optionID: UUID?, before: UUID? = nil, now: Date = Date()) {
        guard let dbID = pages[rowID]?.parentID, let group = pages[dbID]?.database?.groupProperty else { return }
        pages[rowID]?.setValue(optionID.map { PropertyValue.select($0) }, for: group.id)
        if let before, before != rowID {
            var ids = children(of: dbID).map(\.id).filter { $0 != rowID }
            let index = ids.firstIndex(of: before) ?? ids.count
            ids.insert(rowID, at: index)
            reorder(ids)
        }
        touch(rowID, now: now)
    }

    // MARK: - Database columns

    @discardableResult
    public mutating func addProperty(to databaseID: UUID, name: String, type: PropertyType) -> UUID? {
        guard pages[databaseID]?.database != nil else { return nil }
        var property = PropertyDefinition(name: name, type: type)
        if type.hasOptions {
            property.options = [SelectOption(name: "Option 1", color: .blue)]
        }
        pages[databaseID]?.database?.properties.append(property)
        return property.id
    }

    /// Changes a property's type, converting each row's value where it can.
    public mutating func changePropertyType(_ propertyID: UUID, in databaseID: UUID, to type: PropertyType) {
        guard var schema = pages[databaseID]?.database,
              let index = schema.properties.firstIndex(where: { $0.id == propertyID }) else { return }
        let old = schema.properties[index]
        guard old.type != type else { return }
        var property = old
        property.type = type
        // Text columns turn their words into options, so they don't need a starter option.
        if type.hasOptions && property.options.isEmpty && old.type != .text && old.type != .url {
            property.options = [SelectOption(name: "Option 1", color: .blue)]
        }
        // Text becomes options, so "High" in a text column becomes the "High" option.
        var optionsByName: [String: UUID] = Dictionary(property.options.map { ($0.name.lowercased(), $0.id) },
                                                       uniquingKeysWith: { first, _ in first })
        let colors = TagColor.allCases
        for row in children(of: databaseID, includeTrashed: true) {
            let value = row.value(propertyID)
            var converted: PropertyValue?
            switch (value, type) {
            case (nil, _): converted = nil
            case (.text(let s)?, .select), (.url(let s)?, .select):
                let key = s.trimmingCharacters(in: .whitespaces).lowercased()
                if key.isEmpty { converted = nil; break }
                if let id = optionsByName[key] {
                    converted = .select(id)
                } else {
                    let option = SelectOption(name: s.trimmingCharacters(in: .whitespaces),
                                              color: colors[property.options.count % colors.count])
                    property.options.append(option)
                    optionsByName[key] = option.id
                    converted = .select(option.id)
                }
            case (.select(let id)?, .multiSelect): converted = .multiSelect([id])
            case (.multiSelect(let ids)?, .select): converted = ids.first.map { PropertyValue.select($0) }
            case (.select(let id)?, .text): converted = old.option(id).map { PropertyValue.text($0.name) }
            case (.multiSelect(let ids)?, .text):
                converted = .text(ids.compactMap { old.option($0)?.name }.joined(separator: ", "))
            case (.number(let n)?, .text): converted = .text(Workspace.format(number: n))
            case (.text(let s)?, .number): converted = Double(s.trimmingCharacters(in: .whitespaces)).map { PropertyValue.number($0) }
            case (.text(let s)?, .url): converted = .url(s)
            case (.url(let s)?, .text): converted = .text(s)
            case (.checkbox(let on)?, .text): converted = .text(on ? "Yes" : "No")
            case (.text(let s)?, .checkbox):
                converted = .checkbox(["yes", "true", "x", "done", "1"].contains(s.lowercased()))
            default: converted = nil
            }
            pages[row.id]?.setValue(converted, for: propertyID)
        }
        schema.properties[index] = property
        pages[databaseID]?.database = schema
    }

    /// Removes a property and every row's value for it.
    public mutating func deleteProperty(_ propertyID: UUID, in databaseID: UUID) {
        pages[databaseID]?.database?.properties.removeAll { $0.id == propertyID }
        if pages[databaseID]?.database?.groupByID == propertyID { pages[databaseID]?.database?.groupByID = nil }
        if pages[databaseID]?.database?.filter?.propertyID == propertyID { pages[databaseID]?.database?.filter = nil }
        if pages[databaseID]?.database?.sort.key == .property(propertyID) { pages[databaseID]?.database?.sort = DatabaseSort() }
        for row in children(of: databaseID, includeTrashed: true) {
            pages[row.id]?.values[propertyID.uuidString] = nil
        }
    }

    /// Removes a select option and clears it from every row.
    public mutating func deleteOption(_ optionID: UUID, of propertyID: UUID, in databaseID: UUID) {
        guard var schema = pages[databaseID]?.database,
              let index = schema.properties.firstIndex(where: { $0.id == propertyID }) else { return }
        schema.properties[index].options.removeAll { $0.id == optionID }
        if var filter = schema.filter, filter.propertyID == propertyID {
            filter.optionIDs.removeAll { $0 == optionID }
            schema.filter = filter
        }
        pages[databaseID]?.database = schema
        for row in children(of: databaseID, includeTrashed: true) {
            switch row.value(propertyID) {
            case .select(let id)? where id == optionID:
                pages[row.id]?.setValue(nil, for: propertyID)
            case .multiSelect(let ids)? where ids.contains(optionID):
                pages[row.id]?.setValue(.multiSelect(ids.filter { $0 != optionID }), for: propertyID)
            default: break
            }
        }
    }

    /// "3", "2.5", not "3.0".
    public static func format(number: Double) -> String {
        if number == number.rounded(), abs(number) < 1e15 { return String(Int64(number)) }
        return String(number)
    }
}

/// One column of a board view.
public struct BoardColumn: Identifiable, Equatable, Sendable {
    /// Nil for the "No Status" column.
    public var option: SelectOption?
    public var title: String
    public var rows: [Page]

    public var id: String { option?.id.uuidString ?? "none" }
}
