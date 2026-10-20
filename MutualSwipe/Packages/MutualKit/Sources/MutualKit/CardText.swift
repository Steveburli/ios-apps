import Foundation

/// A card's text before it's saved.
public struct CardDraft: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var details: String
    public var link: String
    public var tags: [String]

    public init(title: String, subtitle: String = "", details: String = "", link: String = "", tags: [String] = []) {
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.link = link
        self.tags = tags
    }
}

public enum CardText {
    /// Trims and limits each field the way the web app did, and keeps only
    /// http(s) links. Returns nil without a title.
    public static func clean(title: String, subtitle: String = "", details: String = "", link: String = "",
                             tags: String = "") -> CardDraft? {
        clean(CardDraft(title: title, subtitle: subtitle, details: details, link: link, tags: splitTags(tags)))
    }

    public static func clean(_ draft: CardDraft) -> CardDraft? {
        let title = limit(draft.title, 120)
        guard !title.isEmpty else { return nil }
        let tags = draft.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(6)
            .map { String($0.prefix(30)) }
        return CardDraft(title: title, subtitle: limit(draft.subtitle, 160), details: limit(draft.details, 1500),
                         link: safeURL(draft.link), tags: Array(tags))
    }

    public static func splitTags(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func limit(_ text: String, _ count: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(count))
    }

    /// An https link, adding "https://" when there's no scheme. Anything that
    /// isn't http or https becomes empty.
    public static func safeURL(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let hasScheme = text.range(of: "^[a-zA-Z]+://", options: .regularExpression) != nil
        guard let url = URL(string: hasScheme ? text : "https://" + text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return "" }
        return url.absoluteString
    }

    /// "nytimes.com" for "https://www.nytimes.com/…".
    public static func host(_ link: String) -> String {
        guard let host = URL(string: link)?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The big letter on a card: the first letter, skipping "the", "a" or "an".
    public static func initial(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "^(the|a|an)\\s+", options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(range)
        }
        guard let first = text.first else { return "?" }
        return String(first).uppercased()
    }

    /// A stable 0–7 color for a card, from the same hash the web app used.
    public static func colorIndex(_ seed: String) -> Int {
        var hash: UInt32 = 7
        for scalar in seed.unicodeScalars {
            hash = hash &* 31 &+ scalar.value
        }
        return Int(hash % 8)
    }

    /// "Paste a list": one card per line, `Title | quick facts | details | link`.
    /// Bullets and numbers at the start of a line are dropped.
    public static func parseList(_ text: String) -> [CardDraft] {
        text.components(separatedBy: .newlines).compactMap { line in
            var line = line
            if let bullet = line.range(of: "^\\s*(?:[-*•]|\\d+[.)])\\s+", options: .regularExpression) {
                line.removeSubrange(bullet)
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            func part(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
            return clean(CardDraft(title: part(0), subtitle: part(1), details: part(2), link: part(3)))
        }
    }
}
