import Foundation

/// The Results tab as plain text other apps can read, such as
/// Burlison's Pantry's "Paste results from Mutual".
public enum ResultsExport {
    /// A CSV with a `title,result` header and one row per card, in swipe
    /// order. `result` is the tier label (Super match, Match, Worth a pitch,
    /// Split, Trash, or Waiting on votes).
    public static func csv(_ state: DeckState) -> String {
        var lines = ["title,result"]
        for card in state.cards {
            lines.append(cell(card.title) + "," + cell(state.verdict(for: card).label))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// True once at least one card has a result worth sharing.
    public static func hasResults(_ state: DeckState) -> Bool {
        state.cards.contains { state.verdict(for: $0) != .pending }
    }

    static func cell(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard flat.contains(where: { $0 == "," || $0 == "\"" }) || flat != flat.trimmingCharacters(in: .whitespaces) else {
            return flat
        }
        return "\"" + flat.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
