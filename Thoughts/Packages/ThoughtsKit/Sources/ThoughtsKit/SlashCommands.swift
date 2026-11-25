import Foundation

/// What picking an item from the "/" menu does.
public enum SlashAction: Equatable, Hashable, Sendable {
    case turnInto(BlockKind)
    /// A new subpage, linked from this spot.
    case newPage
    /// A new database subpage, linked from this spot.
    case newDatabase
}

public struct SlashCommand: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var symbol: String
    public var keywords: [String]
    public var action: SlashAction
}

/// The "/" menu: type "/" in a block, then a few letters to narrow it.
public enum SlashCommands {
    public static let all: [SlashCommand] = {
        func turn(_ kind: BlockKind, _ subtitle: String, _ keywords: [String]) -> SlashCommand {
            SlashCommand(id: kind.rawValue, title: kind.displayName, subtitle: subtitle, symbol: kind.symbol,
                         keywords: keywords, action: .turnInto(kind))
        }
        return [
            turn(.text, "Just start writing.", ["plain", "paragraph"]),
            SlashCommand(id: "page", title: "Page", subtitle: "A page inside this page.", symbol: "doc.text",
                         keywords: ["subpage", "new", "link"], action: .newPage),
            turn(.todo, "Track tasks with a checkbox.", ["todo", "checkbox", "task", "check"]),
            turn(.heading1, "Big section heading.", ["h1", "title", "#"]),
            turn(.heading2, "Medium section heading.", ["h2", "subtitle", "##"]),
            turn(.heading3, "Small section heading.", ["h3", "###"]),
            turn(.bulleted, "A simple bulleted list.", ["bullet", "unordered", "ul", "-"]),
            turn(.numbered, "A list with numbering.", ["number", "ordered", "ol", "1."]),
            turn(.toggle, "Hide and show content inside.", ["collapse", "expand", "details", ">"]),
            turn(.quote, "Capture a quote.", ["blockquote", "citation", "\""]),
            turn(.callout, "Make writing stand out.", ["note", "tip", "info", "warning", "highlight"]),
            turn(.divider, "Visually divide blocks.", ["line", "hr", "separator", "rule", "---"]),
            turn(.code, "Capture a code snippet.", ["snippet", "monospace", "pre", "```"]),
            SlashCommand(id: "database", title: "Database", subtitle: "A table and board of pages.",
                         symbol: "tablecells", keywords: ["table", "board", "kanban", "list", "db", "tracker"],
                         action: .newDatabase),
        ]
    }()

    /// Commands matching the letters typed after "/". Title starts first, then keyword starts,
    /// then titles that contain the letters.
    public static func filter(_ query: String) -> [SlashCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        var ranked: [(Int, Int, SlashCommand)] = []
        for (index, command) in all.enumerated() {
            let title = command.title.lowercased()
            let words = title.split(separator: " ").map(String.init)
            let rank: Int
            if title.hasPrefix(q) {
                rank = 0
            } else if words.contains(where: { $0.hasPrefix(q) }) || command.keywords.contains(where: { $0.hasPrefix(q) }) {
                rank = 1
            } else if title.contains(q) {
                rank = 2
            } else {
                continue
            }
            ranked.append((rank, index, command))
        }
        return ranked.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2)
    }

    /// The "/word" being typed at the end of a block's text, if the menu should be open:
    /// the query (letters after the slash) and the UTF-16 offset where the slash is.
    public static func activeQuery(in text: String) -> (query: String, slashOffset: Int)? {
        guard let slash = text.lastIndex(of: "/") else { return nil }
        let before = text[..<slash]
        if let last = before.last, !last.isWhitespace { return nil }
        let query = String(text[text.index(after: slash)...])
        guard query.count <= 20, !query.contains(where: { $0.isNewline }),
              query.filter({ $0 == " " }).count <= 1, !query.hasPrefix(" ") else { return nil }
        return (query, before.utf16.count)
    }

    /// The text with the "/word" taken off the end.
    public static func removingQuery(from text: String) -> String {
        guard let active = activeQuery(in: text) else { return text }
        return text.utf16Prefix(active.slashOffset)
    }
}
