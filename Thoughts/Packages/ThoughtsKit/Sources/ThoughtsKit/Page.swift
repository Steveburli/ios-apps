import Foundation

public enum PageKind: String, Codable, Sendable {
    /// Blocks of writing.
    case document
    /// A collection of row pages with properties, shown as a table, board or list.
    case database
}

/// A page. Pages nest: `parentID` is the page it sits inside, nil for the top level.
/// A page whose parent is a database is one of that database's rows.
public struct Page: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: PageKind
    public var title: String
    /// An emoji, or nil for the plain page symbol.
    public var icon: String?
    /// An index into the app's cover palette, or nil for no cover.
    public var cover: Int?
    public var parentID: UUID?
    /// The order among its siblings, smallest first.
    public var order: Double
    public var blocks: [Block]
    public var created: Date
    public var edited: Date
    /// When it was last opened, for Recents.
    public var opened: Date?
    /// When it was added to Favorites, or nil.
    public var favorited: Date?
    /// When it was put in the Trash, or nil. Its subpages go with it.
    public var trashed: Date?
    /// Databases only.
    public var database: DatabaseSchema?
    /// Rows only: values keyed by property ID (as a string, so the JSON stays an object).
    public var values: [String: PropertyValue]

    public init(id: UUID = UUID(), kind: PageKind = .document, title: String = "", icon: String? = nil,
                cover: Int? = nil, parentID: UUID? = nil, order: Double = 0, blocks: [Block] = [],
                created: Date = Date(), edited: Date? = nil, opened: Date? = nil, favorited: Date? = nil,
                trashed: Date? = nil, database: DatabaseSchema? = nil, values: [String: PropertyValue] = [:]) {
        self.id = id
        self.kind = kind
        self.title = title
        self.icon = icon
        self.cover = cover
        self.parentID = parentID
        self.order = order
        self.blocks = blocks
        self.created = created
        self.edited = edited ?? created
        self.opened = opened
        self.favorited = favorited
        self.trashed = trashed
        self.database = database ?? (kind == .database ? DatabaseSchema.starter() : nil)
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = (try? c.decodeIfPresent(PageKind.self, forKey: .kind)) ?? .document
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        cover = try c.decodeIfPresent(Int.self, forKey: .cover)
        parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
        order = try c.decodeIfPresent(Double.self, forKey: .order) ?? 0
        blocks = (try? c.decodeIfPresent([Block].self, forKey: .blocks)) ?? []
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        edited = try c.decodeIfPresent(Date.self, forKey: .edited) ?? created
        opened = try c.decodeIfPresent(Date.self, forKey: .opened)
        favorited = try c.decodeIfPresent(Date.self, forKey: .favorited)
        trashed = try c.decodeIfPresent(Date.self, forKey: .trashed)
        database = try? c.decodeIfPresent(DatabaseSchema.self, forKey: .database)
        values = (try? c.decodeIfPresent([String: PropertyValue].self, forKey: .values)) ?? [:]
        if kind == .database, database == nil { database = DatabaseSchema.starter() }
    }

    /// The title, or "Untitled" when it's blank.
    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    public var isFavorite: Bool { favorited != nil }

    public func value(_ propertyID: UUID) -> PropertyValue? {
        values[propertyID.uuidString]
    }

    public mutating func setValue(_ value: PropertyValue?, for propertyID: UUID) {
        if let value, !value.isEmpty {
            values[propertyID.uuidString] = value
        } else {
            values[propertyID.uuidString] = nil
        }
    }

    /// All the words on the page, title included.
    public var wordCount: Int {
        let all = ([title] + blocks.map(\.text)).joined(separator: " ")
        return all.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// To-dos ticked and total, for the progress line under a page title.
    public var todoProgress: (done: Int, total: Int) {
        let todos = blocks.filter { $0.kind == .todo }
        return (todos.filter(\.checked).count, todos.count)
    }
}
