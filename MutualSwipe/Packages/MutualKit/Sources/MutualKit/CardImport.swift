import Foundation

/// Turning text from anywhere (a paste, an AI's answer, a CSV file, words read
/// off a photo) into card drafts. Every route ends on the same preview screen.
public enum CardImport {
    /// Reads text as CSV when it looks like a spreadsheet with a header row,
    /// otherwise as a list with one card per line.
    public static func parse(_ text: String, isCSV: Bool = false) -> [CardDraft] {
        let text = stripCodeFences(text)
        if isCSV || looksLikeCSV(text) {
            let rows = parseCSV(text)
            if !rows.isEmpty { return rows }
        }
        return parseLines(text)
    }

    /// One card per line. A line can be `Title | quick facts | details | link`,
    /// or `Title - details`, or `Title, details`. Headings an AI adds around a
    /// list ("Here are 10 movies:") and Markdown bold are dropped.
    public static func parseLines(_ text: String) -> [CardDraft] {
        let lines = text.components(separatedBy: .newlines)
        let barred = lines.filter { $0.contains("|") }.count
        return lines.compactMap { raw -> CardDraft? in
            var line = raw.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            if let bullet = line.range(of: "^\\s*(?:[-*•]|\\d+[.)])\\s+", options: .regularExpression) {
                line.removeSubrange(bullet)
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasSuffix(":"), !line.hasPrefix("#") else { return nil }
            // A Markdown table's divider row.
            if line.range(of: "^\\|?[\\s:|-]+\\|?$", options: .regularExpression) != nil, line.contains("-") { return nil }
            if line.contains("|") {
                var parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                // Markdown tables start and end with a bar.
                if parts.first == "" { parts.removeFirst() }
                if parts.last == "" { parts.removeLast() }
                func part(_ i: Int) -> String { i < parts.count ? parts[i] : "" }
                // A table's header row.
                if ["title", "name"].contains(part(0).lowercased()) { return nil }
                return CardText.clean(CardDraft(title: part(0), subtitle: part(1), details: part(2), link: part(3),
                                                tags: CardText.splitTags(part(4))))
            }
            // When most lines use bars, a line without one is chatter, not a card.
            if barred >= 3 && barred * 2 >= lines.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count {
                return nil
            }
            let (title, details) = splitTitle(line)
            return CardText.clean(CardDraft(title: title, details: details))
        }
    }

    /// "Thai Basil - great pad see ew" → ("Thai Basil", "great pad see ew").
    /// A spaced dash wins over a comma, so "Crouching Tiger, Hidden Dragon - 2000" splits at the dash.
    public static func splitTitle(_ line: String) -> (String, String) {
        for dash in [" - ", " – ", " — "] {
            if let range = line.range(of: dash) {
                return (String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                        String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces))
            }
        }
        if let range = line.range(of: ", ") {
            return (String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                    String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces))
        }
        return (line, "")
    }

    // MARK: CSV

    private static let headerNames: [String: Column] = [
        "title": .title, "name": .title, "card": .title, "item": .title, "option": .title,
        "quick facts": .subtitle, "facts": .subtitle, "subtitle": .subtitle, "summary": .subtitle,
        "details": .details, "description": .details, "notes": .details, "note": .details, "about": .details,
        "link": .link, "url": .link, "website": .link, "web": .link,
        "tags": .tags, "tag": .tags, "category": .tags, "categories": .tags, "good for": .tags,
    ]

    private enum Column { case title, subtitle, details, link, tags }

    static func looksLikeCSV(_ text: String) -> Bool {
        guard let first = text.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return false
        }
        let cells = splitCSVRows(first).first ?? []
        return cells.count >= 2 && cells.contains { headerNames[normalize($0)] == .title }
    }

    /// A spreadsheet saved as CSV. With a header row, columns are matched by
    /// name (title or name, quick facts, details or description, link or
    /// website, tags). Without one, they're taken in that order.
    public static func parseCSV(_ text: String) -> [CardDraft] {
        var rows = splitCSVRows(text).filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !rows.isEmpty else { return [] }
        var columns: [Column?] = [.title, .subtitle, .details, .link, .tags]
        let header = rows[0].map { headerNames[normalize($0)] }
        if header.contains(where: { $0 == .title }) {
            columns = header
            rows.removeFirst()
        }
        return rows.compactMap { row in
            var draft = CardDraft(title: "")
            for (index, cell) in row.enumerated() where index < columns.count {
                let value = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                switch columns[index] {
                case .title?: draft.title = value
                case .subtitle?: draft.subtitle = value
                case .details?: draft.details = draft.details.isEmpty ? value : draft.details + "\n" + value
                case .link?: draft.link = value
                case .tags?: draft.tags += CardText.splitTags(value.replacingOccurrences(of: ";", with: ","))
                case nil: break
                }
            }
            return CardText.clean(draft)
        }
    }

    private static func normalize(_ header: String) -> String {
        header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    /// Splits CSV into rows of cells, honoring quotes (`"a, b"` and `""` for a quote).
    /// Tabs separate cells too, for lists copied out of a spreadsheet.
    static func splitCSVRows(_ text: String) -> [[String]] {
        let separator: Character = text.contains("\t") && !text.contains(",") ? "\t" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var chars = Array(text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        cell.append("\"")
                        i += 1
                    } else {
                        quoted = false
                    }
                } else {
                    cell.append(c)
                }
            } else if c == "\"" && cell.trimmingCharacters(in: .whitespaces).isEmpty {
                cell = ""
                quoted = true
            } else if c == separator {
                row.append(cell)
                cell = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(cell)
                cell = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                cell.append(c)
            }
            i += 1
        }
        return rows
    }

    private static func stripCodeFences(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .joined(separator: "\n")
    }

    // MARK: Asking an AI

    /// A prompt to copy into any AI app. Its answer pastes straight back in.
    public static func aiPrompt(for request: String, kind: DeckKind, deckTitle: String) -> String {
        let ask = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = ask.isEmpty ? "\(kind.plural.lowercased()) for a deck called “\(deckTitle)”" : ask
        return """
        Make a list for a swiping app where friends vote on options. The list: \(topic).

        Give 15 to 30 options, one per line, in exactly this format, with nothing before or after the list:
        Title | quick facts | one or two sentences on what it is and why it's worth a look | website link

        Quick facts are a few words, like "\(kind.hint)". Leave the link empty if you aren't sure of the real address. Only include options that really exist.
        """
    }
}
