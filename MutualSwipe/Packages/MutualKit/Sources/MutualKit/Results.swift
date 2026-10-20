import Foundation

/// Where a card lands once everyone has voted.
public enum Verdict: String, CaseIterable, Sendable {
    /// Everyone super liked it.
    case perfect
    /// Every vote was a like or a super like.
    case match
    /// Someone super liked it and someone rejected it.
    case debate
    /// Likes and rejects, no super likes.
    case split
    /// Someone super rejected it, or everyone rejected it.
    case trash
    /// Not everyone has voted.
    case pending

    public var label: String {
        switch self {
        case .perfect: return "Super match"
        case .match: return "Match"
        case .debate: return "Worth a pitch"
        case .split: return "Split"
        case .trash: return "Trash"
        case .pending: return "Waiting on votes"
        }
    }

    /// Heading on the Results tab, worded for how many people voted.
    public func title(people n: Int) -> String {
        switch self {
        case .perfect: return n == 1 ? "You super liked" : n == 2 ? "You both super liked" : "Everyone super liked"
        case .match: return n == 1 ? "You liked" : n == 2 ? "You both like it" : "Everyone’s in"
        case .debate: return "Worth a pitch"
        case .split: return "Split"
        case .trash: return "Trash"
        case .pending: return "Waiting on votes"
        }
    }

    public var note: String {
        switch self {
        case .perfect: return "Unanimous. Start here."
        case .match: return "Every vote was a like or a super like."
        case .debate: return "Someone super liked it and someone rejected it. Hear them out."
        case .split: return "A mix of likes and rejects, with no super likes."
        case .trash: return "Someone super rejected it, or everyone rejected it."
        case .pending: return ""
        }
    }

    /// Split and Trash start folded away.
    public var startsCollapsed: Bool {
        self == .split || self == .trash
    }

    /// The tiers in the order they're shown.
    public static let shown: [Verdict] = [.perfect, .match, .debate, .split, .trash]

    public var isMatch: Bool {
        self == .perfect || self == .match
    }
}

/// Everything the Swipe and Results tabs need for one deck.
public struct DeckState: Sendable {
    public let cards: [Card]
    /// The people who've voted on this deck, plus you, in the order they joined.
    public let participants: [String]
    /// Player ID → card ID → vote.
    public let picks: [String: [String: Vote]]
    public let groups: [Verdict: [Card]]
    /// Your remaining cards, skipping any someone else super rejected.
    public let queue: [Card]
    /// Player ID → cards voted.
    public let progress: [String: Int]

    public init(cards: [Card], players: [Player], picks allPicks: [Pick], me: String?) {
        let cards = cards.inSwipeOrder()
        let cardIDs = Set(cards.map(\.id))
        var byPlayer: [String: [String: Vote]] = [:]
        for pick in allPicks where cardIDs.contains(pick.cardID) {
            byPlayer[pick.playerID, default: [:]][pick.cardID] = pick.vote
        }
        if let me, byPlayer[me] == nil, players.contains(where: { $0.id == me }) {
            byPlayer[me] = [:]
        }
        let ordered = players.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let participants = ordered.map(\.id).filter { byPlayer[$0] != nil }

        var groups: [Verdict: [Card]] = [:]
        for verdict in Verdict.allCases { groups[verdict] = [] }
        for card in cards {
            groups[DeckState.classify(card.id, participants: participants, picks: byPlayer), default: []].append(card)
        }

        func vetoedByOther(_ card: Card, _ playerID: String) -> Bool {
            participants.contains { $0 != playerID && byPlayer[$0]?[card.id] == .never }
        }

        var progress: [String: Int] = [:]
        for id in participants {
            progress[id] = cards.filter { byPlayer[id]?[$0.id] != nil }.count
        }

        let queue: [Card]
        if let me, let mine = byPlayer[me] {
            queue = cards.filter { mine[$0.id] == nil && !vetoedByOther($0, me) }
        } else {
            queue = cards
        }

        self.cards = cards
        self.participants = participants
        self.picks = byPlayer
        self.groups = groups
        self.queue = queue
        self.progress = progress
    }

    public static func classify(_ cardID: String, participants: [String], picks: [String: [String: Vote]]) -> Verdict {
        let cast = participants.compactMap { picks[$0]?[cardID] }
        if cast.contains(.never) { return .trash }
        if participants.isEmpty || cast.count < participants.count { return .pending }
        if cast.allSatisfy({ $0 == .nope }) { return .trash }
        if cast.allSatisfy({ $0 == .love }) { return .perfect }
        if cast.allSatisfy({ $0 == .love || $0 == .like }) { return .match }
        if cast.contains(.love) { return .debate }
        return .split
    }

    public func verdict(for card: Card) -> Verdict {
        DeckState.classify(card.id, participants: participants, picks: picks)
    }

    public func cards(_ verdict: Verdict) -> [Card] {
        groups[verdict] ?? []
    }

    public var matchCount: Int {
        cards(.perfect).count + cards(.match).count
    }

    /// Cards a person still has to swipe.
    public func remaining(for playerID: String) -> Int {
        let mine = picks[playerID] ?? [:]
        return cards.filter { card in
            mine[card.id] == nil && !participants.contains { $0 != playerID && picks[$0]?[card.id] == .never }
        }.count
    }

    public func vote(of playerID: String, on cardID: String) -> Vote? {
        picks[playerID]?[cardID]
    }

    /// People who've voted on at least one card.
    public var activeParticipants: [String] {
        participants.filter { (progress[$0] ?? 0) > 0 }
    }
}
