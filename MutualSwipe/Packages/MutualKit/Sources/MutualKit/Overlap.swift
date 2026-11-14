import Foundation

/// The Overlap tab: each circle is one option (a card), and each person sits
/// inside every circle they liked or super liked. Up to three circles show at
/// once, since more can't overlap cleanly on a phone.
public enum Overlap {
    /// The most circles shown at once.
    public static let maxCircles = 3

    /// True for a like or a super like.
    public static func isFan(_ vote: Vote?) -> Bool {
        vote == .like || vote == .love
    }

    /// The cards the picture can show: every card that isn't retired.
    public static func options(_ state: DeckState) -> [Card] {
        state.cards.filter { !$0.isRetired }
    }

    /// People who liked or super liked a card, in the order they joined.
    public static func fans(of cardID: String, in state: DeckState) -> [String] {
        state.participants.filter { isFan(state.vote(of: $0, on: cardID)) }
    }

    /// The circles the picture starts with: the most-liked cards, ties going
    /// to more super likes, then swipe order. Cards nobody liked are left out.
    public static func startingCards(_ state: DeckState, count: Int = maxCircles) -> [String] {
        let ranked = options(state).enumerated().map { index, card -> (card: Card, fans: Int, loves: Int, index: Int) in
            let fans = fans(of: card.id, in: state).count
            let loves = state.participants.filter { state.vote(of: $0, on: card.id) == .love }.count
            return (card, fans, loves, index)
        }
        .filter { $0.fans > 0 }
        .sorted { a, b in
            if a.fans != b.fans { return a.fans > b.fans }
            if a.loves != b.loves { return a.loves > b.loves }
            return a.index < b.index
        }
        return ranked.prefix(count).map(\.card.id)
    }

    /// Which of the shown circles each person sits in, as indexes into `shown`.
    /// Everyone who's voted is included; an empty set means they liked none of them.
    public static func membership(_ state: DeckState, shown: [String]) -> [String: Set<Int>] {
        var result: [String: Set<Int>] = [:]
        for person in state.participants {
            var inside = Set<Int>()
            for (index, cardID) in shown.enumerated() where isFan(state.vote(of: person, on: cardID)) {
                inside.insert(index)
            }
            result[person] = inside
        }
        return result
    }

    /// People in one area of the picture, in the order they joined: those who
    /// liked exactly these circles and none of the other shown ones.
    public static func people(in area: Set<Int>, state: DeckState, shown: [String]) -> [String] {
        let inside = membership(state, shown: shown)
        return state.participants.filter { inside[$0] == area }
    }

    /// People who liked every card in `cards` (and maybe others too): what
    /// tapping a circle or a crossing shows.
    public static func people(likingAll cards: [String], state: DeckState) -> [String] {
        guard !cards.isEmpty else { return [] }
        return state.participants.filter { person in
            cards.allSatisfy { isFan(state.vote(of: person, on: $0)) }
        }
    }

    /// Cards this person super liked that nobody else liked or super liked.
    public static func onlyLovedBy(_ person: String, in state: DeckState) -> [Card] {
        options(state).filter { card in
            state.vote(of: person, on: card.id) == .love
                && !state.participants.contains { $0 != person && isFan(state.vote(of: $0, on: card.id)) }
        }
    }

    /// A short, friendly invite to do a solo-loved card with other people.
    /// It names only the card, never the group, the deck or anyone in it.
    public static func inviteMessage(for card: Card, kind: DeckKind) -> String {
        let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .movies:
            return "Anyone want to watch \(title) with me? I’d love some company. Let me know if you’re in!"
        case .recipes:
            return "I’m thinking of making \(title). Anyone want to cook it with me, or come eat? Let me know!"
        case .restaurants:
            return "I’ve been wanting to try \(title). Anyone up for going with me? Let me know if you’re in!"
        case .travel:
            return "I’m dreaming about \(title). Anyone want to plan a trip together? Let me know if you’re interested!"
        case .dates, .other:
            return "Anyone up for \(title)? I’m looking for people to do it with. Let me know if you want to join!"
        }
    }
}
