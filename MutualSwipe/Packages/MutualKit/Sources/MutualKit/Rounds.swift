import Foundation

/// One finished round, kept in the deck's history.
public struct RoundResult: Identifiable, Codable, Equatable, Sendable {
    public var roundID: String
    public var question: String
    public var cardID: String
    /// Saved with the result so the history still reads right if the card is deleted.
    public var title: String
    public var at: Date

    public var id: String { roundID }

    public init(roundID: String, question: String, cardID: String, title: String, at: Date) {
        self.roundID = roundID
        self.question = question
        self.cardID = cardID
        self.title = title
        self.at = at
    }
}

/// How far each person has got through a deck's first pass (vetting).
public struct Vetting: Sendable {
    /// Player ID → share of the deck swiped, 0 to 1.
    public let share: [String: Double]
    /// The whole group's share: every person's swipes over every person's cards.
    public let group: Double
    /// People who've swiped every card, in the order given.
    public let vetted: [String]

    /// `players` is everyone in the group, in order. A card someone else said
    /// Never to counts as done, because it never reaches your stack.
    public init(state: DeckState, players: [String]) {
        let total = state.cards.count
        var share: [String: Double] = [:]
        var vetted: [String] = []
        var done = 0
        for id in players {
            let mine = total - state.remaining(for: id)
            done += mine
            share[id] = total == 0 ? 0 : Double(mine) / Double(total)
            if total > 0 && mine == total { vetted.append(id) }
        }
        self.share = share
        self.vetted = vetted
        self.group = total == 0 || players.isEmpty ? 0 : Double(done) / Double(total * players.count)
    }

    /// "45%", rounded down so 99.6% never shows as 100%.
    public static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded(.down)))%"
    }
}

/// Rounds: quick picks for right now from a deck, like "Which do you want tonight?".
public enum Rounds {
    public static let defaultQuestion = "Which do you want tonight?"
    /// How many past winners a deck keeps.
    public static let historyLimit = 50

    /// What a new round would start with.
    public struct Plan: Equatable, Sendable {
        public let cards: [Card]
        /// The deck is vetted, so the round uses only cards everyone liked or loved.
        public let usesVetting: Bool
        /// The words the cards were narrowed to, when any matched.
        public let narrowedBy: [String]
    }

    /// A vetted deck (everyone who swiped it has swiped every card) uses only the
    /// cards everyone liked or loved, as long as that leaves at least two. Otherwise
    /// the round uses every card except ones someone said Never to in vetting.
    /// A chained round then keeps only cards that mention one of `filter`'s
    /// words, unless that would leave none.
    public static func plan(vetting state: DeckState, filter: [String] = []) -> Plan {
        let swipers = state.activeParticipants
        let vetted = !swipers.isEmpty && swipers.allSatisfy { state.remaining(for: $0) == 0 }
        let liked = state.spinCandidates
        var pool: [Card]
        var usesVetting = false
        if vetted && liked.count >= 2 {
            pool = state.cards.filter { card in liked.contains { $0.id == card.id } }
            usesVetting = true
        } else {
            pool = state.cards.filter { card in !swipers.contains { state.vote(of: $0, on: card.id) == .never } }
        }
        let words = filter.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var narrowedBy: [String] = []
        if !words.isEmpty {
            let narrowed = pool.filter { card in words.contains { mentions(card, $0) } }
            if !narrowed.isEmpty {
                pool = narrowed
                narrowedBy = words
            }
        }
        return Plan(cards: pool, usesVetting: usesVetting, narrowedBy: narrowedBy)
    }

    /// Whether a card's title, quick facts, details or tags mention a word.
    public static func mentions(_ card: Card, _ word: String) -> Bool {
        let haystack = ([card.title, card.subtitle, card.details] + card.tags).joined(separator: " ")
        return haystack.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The round's winner so far: the card marked decided, else the spinner's
    /// pick, else the first Super match, else the first Match.
    public static func winner(of state: DeckState, decided: [String], spin: String?) -> Card? {
        if let id = decided.last(where: { id in state.cards.contains { $0.id == id } }) {
            return state.cards.first { $0.id == id }
        }
        if let spin, let card = state.spinCandidates.first(where: { $0.id == spin }) { return card }
        return state.cards(.perfect).first ?? state.cards(.match).first
    }

    /// Adds or replaces a round's result, keeping the newest `historyLimit`.
    public static func record(_ result: RoundResult, in history: [RoundResult]) -> [RoundResult] {
        var list = history.filter { $0.roundID != result.roundID }
        list.append(result)
        list.sort { $0.at < $1.at }
        return Array(list.suffix(historyLimit))
    }
}
