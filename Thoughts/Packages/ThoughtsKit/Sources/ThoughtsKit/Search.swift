import Foundation

public struct SearchResult: Identifiable, Equatable, Sendable {
    public var pageID: UUID
    /// True when the title matched, not just the writing.
    public var inTitle: Bool
    /// A bit of the writing around the first match, if the match was in the writing.
    public var snippet: String?

    public var id: UUID { pageID }
}

extension Workspace {
    /// Pages whose title or writing contains every word of the query, ignoring case and accents.
    /// Title matches come first (title starts before title contains), then the most recently edited.
    public func search(_ query: String, limit: Int = 50) -> [SearchResult] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map { Workspace.fold(String($0)) }
        guard !words.isEmpty else { return [] }
        var found: [(rank: Int, edited: Date, result: SearchResult)] = []
        for page in pages.values where !isInTrash(page.id) {
            let title = Workspace.fold(page.displayTitle.lowercased())
            let body = page.blocks.map(\.text)
            let foldedBody = body.map { Workspace.fold($0.lowercased()) }
            let rowValues = page.values.values.compactMap { value -> String? in
                switch value {
                case .text(let s), .url(let s): return Workspace.fold(s.lowercased())
                default: return nil
                }
            }
            let everything = ([title] + foldedBody + rowValues).joined(separator: "\n")
            guard words.allSatisfy({ everything.contains($0) }) else { continue }
            let inTitle = words.allSatisfy { title.contains($0) }
            let rank: Int
            if inTitle {
                rank = title.hasPrefix(words[0]) ? 0 : 1
            } else {
                rank = 2
            }
            var snippet: String?
            if !inTitle || rank > 0 {
                if let line = foldedBody.firstIndex(where: { line in words.contains { line.contains($0) } }) {
                    snippet = Workspace.snippet(body[line], around: words.first { foldedBody[line].contains($0) } ?? words[0])
                }
            }
            found.append((rank, page.edited, SearchResult(pageID: page.id, inTitle: inTitle, snippet: snippet)))
        }
        return Array(found.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            return a.edited > b.edited
        }.prefix(limit).map(\.result))
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// About 80 characters of `text` around the first place `word` appears.
    static func snippet(_ text: String, around word: String, width: Int = 80) -> String {
        let folded = fold(text.lowercased())
        guard folded.count == text.count, let range = folded.range(of: word) else {
            return String(text.prefix(width))
        }
        let start = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let from = max(0, start - width / 3)
        let to = min(text.count, from + width)
        let startIndex = text.index(text.startIndex, offsetBy: from)
        let endIndex = text.index(text.startIndex, offsetBy: to)
        var piece = String(text[startIndex..<endIndex]).replacingOccurrences(of: "\n", with: " ")
        if from > 0 { piece = "…" + piece }
        if to < text.count { piece += "…" }
        return piece
    }
}
