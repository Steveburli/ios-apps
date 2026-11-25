import Foundation

/// Markdown-style shortcuts typed at the start of a text block, like "# " for a heading.
public enum MarkdownShortcut {
    public struct Match: Equatable, Sendable {
        public var kind: BlockKind
        public var checked: Bool
        /// The text left after the shortcut is taken off.
        public var rest: String
    }

    private static let prefixes: [(String, BlockKind, Bool)] = [
        ("### ", .heading3, false),
        ("## ", .heading2, false),
        ("# ", .heading1, false),
        ("- ", .bulleted, false),
        ("* ", .bulleted, false),
        ("+ ", .bulleted, false),
        ("• ", .bulleted, false),
        ("[] ", .todo, false),
        ("[ ] ", .todo, false),
        ("[x] ", .todo, true),
        ("[X] ", .todo, true),
        ("> ", .toggle, false),
        ("\" ", .quote, false),
        ("\u{201C} ", .quote, false),
        ("\u{201D} ", .quote, false),
        ("| ", .quote, false),
        ("```", .code, false),
    ]

    /// The shortcut at the start of `text`, if any. Only plain text blocks turn into something else.
    public static func match(_ text: String, in kind: BlockKind = .text) -> Match? {
        guard kind == .text else { return nil }
        if text == "---" || text == "***" || text == "\u{2014}-" {
            return Match(kind: .divider, checked: false, rest: "")
        }
        for (prefix, target, checked) in prefixes where text.hasPrefix(prefix) {
            return Match(kind: target, checked: checked, rest: String(text.dropFirst(prefix.count)))
        }
        // "1. " or "1) " for a numbered list.
        if let space = text.firstIndex(of: " ") {
            let head = text[..<space]
            if head.count >= 2, let last = head.last, last == "." || last == ")",
               head.dropLast().allSatisfy(\.isNumber) {
                return Match(kind: .numbered, checked: false, rest: String(text[text.index(after: space)...]))
            }
        }
        return nil
    }
}
