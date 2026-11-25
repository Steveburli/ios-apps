import Foundation

/// What a block is. A page's body is a flat list of blocks; nesting is `Block.indent`.
public enum BlockKind: String, Codable, CaseIterable, Sendable {
    case text
    case heading1
    case heading2
    case heading3
    case bulleted
    case numbered
    case todo
    case toggle
    case quote
    case callout
    case divider
    case code
    case pageLink

    /// Dividers and page links have no text of their own to edit.
    public var hasText: Bool {
        self != .divider && self != .pageLink
    }

    /// Lists carry on to the next line when you press Return.
    public var continuesOnReturn: Bool {
        switch self {
        case .bulleted, .numbered, .todo, .toggle: return true
        default: return false
        }
    }

    /// Return types a new line inside a code block instead of starting a new block.
    public var keepsNewlines: Bool {
        self == .code
    }

    public var isHeading: Bool {
        self == .heading1 || self == .heading2 || self == .heading3
    }

    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulleted: return "Bulleted list"
        case .numbered: return "Numbered list"
        case .todo: return "To-do list"
        case .toggle: return "Toggle list"
        case .quote: return "Quote"
        case .callout: return "Callout"
        case .divider: return "Divider"
        case .code: return "Code"
        case .pageLink: return "Page"
        }
    }

    /// The SF Symbol used in menus.
    public var symbol: String {
        switch self {
        case .text: return "textformat"
        case .heading1: return "textformat.size.larger"
        case .heading2: return "textformat.size"
        case .heading3: return "textformat.size.smaller"
        case .bulleted: return "list.bullet"
        case .numbered: return "list.number"
        case .todo: return "checkmark.square"
        case .toggle: return "chevron.right.circle"
        case .quote: return "text.quote"
        case .callout: return "lightbulb"
        case .divider: return "minus"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .pageLink: return "doc.text"
        }
    }

    /// Kinds offered under "Turn into".
    public static let turnIntoChoices: [BlockKind] = [
        .text, .heading1, .heading2, .heading3, .bulleted, .numbered, .todo, .toggle, .quote, .callout, .code,
    ]
}

/// One line (or paragraph) of a page.
public struct Block: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var kind: BlockKind
    public var text: String
    /// How far the block is nested under the blocks above it, 0 to `Block.maxIndent`.
    public var indent: Int
    /// To-dos only.
    public var checked: Bool
    /// Toggles only: when true the blocks nested under it are hidden.
    public var collapsed: Bool
    /// Callouts only: the emoji at the start.
    public var icon: String?
    /// Page links only.
    public var linkedPageID: UUID?

    public static let maxIndent = 6

    public init(id: UUID = UUID(), kind: BlockKind = .text, text: String = "", indent: Int = 0,
                checked: Bool = false, collapsed: Bool = false, icon: String? = nil, linkedPageID: UUID? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.indent = indent
        self.checked = checked
        self.collapsed = collapsed
        self.icon = icon
        self.linkedPageID = linkedPageID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = (try? c.decodeIfPresent(BlockKind.self, forKey: .kind)) ?? .text
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        indent = try c.decodeIfPresent(Int.self, forKey: .indent) ?? 0
        checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        linkedPageID = try c.decodeIfPresent(UUID.self, forKey: .linkedPageID)
    }

    /// Changes the kind, clearing what no longer applies.
    public mutating func turn(into newKind: BlockKind) {
        kind = newKind
        if newKind != .todo { checked = false }
        if newKind != .toggle { collapsed = false }
        if newKind == .callout, icon == nil { icon = "💡" }
        if newKind == .divider { text = "" }
        if newKind != .pageLink { linkedPageID = nil }
    }
}
