import Foundation

/// The colors a select option or tag can be.
public enum TagColor: String, Codable, CaseIterable, Sendable {
    case gray, brown, orange, yellow, green, blue, purple, pink, red

    public var name: String { rawValue.capitalized }
}

public struct SelectOption: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var color: TagColor

    public init(id: UUID = UUID(), name: String, color: TagColor = .gray) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// The kinds of database columns.
public enum PropertyType: String, Codable, CaseIterable, Sendable {
    case text, number, select, multiSelect, date, checkbox, url

    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .number: return "Number"
        case .select: return "Select"
        case .multiSelect: return "Multi-select"
        case .date: return "Date"
        case .checkbox: return "Checkbox"
        case .url: return "URL"
        }
    }

    public var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .number: return "number"
        case .select: return "chevron.down.circle"
        case .multiSelect: return "list.bullet.circle"
        case .date: return "calendar"
        case .checkbox: return "checkmark.square"
        case .url: return "link"
        }
    }

    /// Select and multi-select have options; the others don't.
    public var hasOptions: Bool {
        self == .select || self == .multiSelect
    }
}

/// A database column. The page title is always the first column and isn't one of these.
public struct PropertyDefinition: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var type: PropertyType
    public var options: [SelectOption]

    public init(id: UUID = UUID(), name: String, type: PropertyType, options: [SelectOption] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Property"
        type = (try? c.decodeIfPresent(PropertyType.self, forKey: .type)) ?? .text
        options = try c.decodeIfPresent([SelectOption].self, forKey: .options) ?? []
    }

    public func option(_ id: UUID?) -> SelectOption? {
        guard let id else { return nil }
        return options.first { $0.id == id }
    }
}

/// A row's value for one property.
public enum PropertyValue: Codable, Equatable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case select(UUID)
    case multiSelect([UUID])
    case date(Date)
    case checkbox(Bool)
    case url(String)

    /// True for values that show as an empty cell.
    public var isEmpty: Bool {
        switch self {
        case .text(let s), .url(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .multiSelect(let ids): return ids.isEmpty
        case .checkbox(let on): return !on
        case .number, .select, .date: return false
        }
    }

    public var selectID: UUID? {
        if case .select(let id) = self { return id }
        return nil
    }

    public var optionIDs: [UUID] {
        switch self {
        case .select(let id): return [id]
        case .multiSelect(let ids): return ids
        default: return []
        }
    }
}

/// How a database shows its rows.
public enum DatabaseLayout: String, Codable, CaseIterable, Sendable {
    case table, board, list

    public var displayName: String { rawValue.capitalized }

    public var symbol: String {
        switch self {
        case .table: return "tablecells"
        case .board: return "rectangle.split.3x1"
        case .list: return "list.bullet.rectangle"
        }
    }
}

/// What rows are sorted by.
public enum SortKey: Codable, Equatable, Hashable, Sendable {
    /// The order you dragged them into.
    case manual
    case title
    case created
    case edited
    case property(UUID)
}

public struct DatabaseSort: Codable, Equatable, Hashable, Sendable {
    public var key: SortKey
    public var ascending: Bool

    public init(key: SortKey = .manual, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }
}

/// Shows only rows whose select, multi-select or checkbox property matches.
public struct DatabaseFilter: Codable, Equatable, Hashable, Sendable {
    public var propertyID: UUID
    /// Select and multi-select: rows with any of these options.
    public var optionIDs: [UUID]
    /// Checkbox: rows that are (or aren't) ticked.
    public var checked: Bool?

    public init(propertyID: UUID, optionIDs: [UUID] = [], checked: Bool? = nil) {
        self.propertyID = propertyID
        self.optionIDs = optionIDs
        self.checked = checked
    }
}

/// The columns and view settings of a database page. Its rows are its child pages.
public struct DatabaseSchema: Codable, Equatable, Hashable, Sendable {
    public var properties: [PropertyDefinition]
    public var layout: DatabaseLayout
    /// The select property the board groups by. Nil means the first select property.
    public var groupByID: UUID?
    public var sort: DatabaseSort
    public var filter: DatabaseFilter?

    public init(properties: [PropertyDefinition] = [], layout: DatabaseLayout = .table,
                groupByID: UUID? = nil, sort: DatabaseSort = DatabaseSort(), filter: DatabaseFilter? = nil) {
        self.properties = properties
        self.layout = layout
        self.groupByID = groupByID
        self.sort = sort
        self.filter = filter
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        properties = try c.decodeIfPresent([PropertyDefinition].self, forKey: .properties) ?? []
        layout = (try? c.decodeIfPresent(DatabaseLayout.self, forKey: .layout)) ?? .table
        groupByID = try c.decodeIfPresent(UUID.self, forKey: .groupByID)
        sort = (try? c.decodeIfPresent(DatabaseSort.self, forKey: .sort)) ?? DatabaseSort()
        filter = try? c.decodeIfPresent(DatabaseFilter.self, forKey: .filter)
    }

    public func property(_ id: UUID?) -> PropertyDefinition? {
        guard let id else { return nil }
        return properties.first { $0.id == id }
    }

    /// The property the board groups by: the chosen one if it's still a select, else the first select.
    public var groupProperty: PropertyDefinition? {
        if let chosen = property(groupByID), chosen.type == .select { return chosen }
        return properties.first { $0.type == .select }
    }

    /// A new database: a Status select (Not started, In progress, Done) and a Date.
    public static func starter() -> DatabaseSchema {
        let status = PropertyDefinition(name: "Status", type: .select, options: [
            SelectOption(name: "Not started", color: .gray),
            SelectOption(name: "In progress", color: .blue),
            SelectOption(name: "Done", color: .green),
        ])
        let date = PropertyDefinition(name: "Date", type: .date)
        return DatabaseSchema(properties: [status, date], layout: .table, groupByID: status.id)
    }
}
