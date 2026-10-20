import Foundation

/// A new random ID: 32 lowercase hex characters, safe as a CloudKit record name.
public func makeID() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
}

public enum DeckKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case dates, recipes, movies, restaurants, travel, other

    public var id: Self { self }

    public var label: String {
        switch self {
        case .dates: return "Date night"
        case .recipes: return "Recipe"
        case .movies: return "Movie"
        case .restaurants: return "Restaurant"
        case .travel: return "Trip"
        case .other: return "Idea"
        }
    }

    public var plural: String {
        switch self {
        case .dates: return "Date nights"
        case .recipes: return "Recipes"
        case .movies: return "Movies"
        case .restaurants: return "Restaurants"
        case .travel: return "Travel"
        case .other: return "Ideas"
        }
    }

    /// Placeholder for "Quick facts".
    public var hint: String {
        switch self {
        case .dates: return "Cost · time · where"
        case .recipes: return "Cuisine · cook time"
        case .movies: return "Year · genre · runtime"
        case .restaurants: return "Cuisine · area · price"
        case .travel: return "Region · best season"
        case .other: return "A few quick facts"
        }
    }

    /// Placeholder for a card title.
    public var example: String {
        switch self {
        case .dates: return "Sunset picnic"
        case .recipes: return "Thai green curry"
        case .movies: return "Past Lives"
        case .restaurants: return "Name of the place"
        case .travel: return "Kyoto in the fall"
        case .other: return "Name it"
        }
    }
}

/// The four swipes.
public enum Vote: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Swipe up: super like.
    case love = "super"
    /// Swipe right.
    case like
    /// Swipe left: reject.
    case nope
    /// Swipe down: super reject. It also takes the card out of everyone else's stack.
    case never = "veto"

    public var id: Self { self }

    public var label: String {
        switch self {
        case .love: return "Love"
        case .like: return "Like"
        case .nope: return "Nope"
        case .never: return "Never"
        }
    }

    public var stamp: String {
        switch self {
        case .love: return "LOVE IT"
        case .like: return "LIKE"
        case .nope: return "NOPE"
        case .never: return "NEVER"
        }
    }

    public var long: String {
        switch self {
        case .love: return "Super like"
        case .like: return "Like"
        case .nope: return "Reject"
        case .never: return "Super reject"
        }
    }
}

/// People who swipe together. Each group is one iCloud record zone, shared
/// as a whole, so everyone invited sees every deck in it.
public struct SwipeGroup: Identifiable, Codable, Equatable, Sendable {
    /// The zone name.
    public var id: String
    /// The zone owner's CloudKit user record name, or `CKCurrentUserDefaultName` for your own.
    public var ownerName: String
    public var name: String
    public var isOwned: Bool
    public var isShared = false
    /// Names of the people the group is shared with, when known.
    public var participants: [String] = []
    /// You were invited without permission to make changes.
    public var readOnly = false
    public var createdAt: Date
    /// CloudKit's archived system fields for the group record.
    public var systemFields: Data?

    public init(id: String, ownerName: String, name: String, isOwned: Bool, createdAt: Date) {
        self.id = id
        self.ownerName = ownerName
        self.name = name
        self.isOwned = isOwned
        self.createdAt = createdAt
    }
}

public struct Deck: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var groupID: String
    public var title: String
    public var kind: DeckKind
    public var blurb: String
    public var createdAt: Date
    public var systemFields: Data?

    public init(id: String = makeID(), groupID: String, title: String, kind: DeckKind, blurb: String, createdAt: Date) {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.kind = kind
        self.blurb = blurb
        self.createdAt = createdAt
    }
}

public struct Card: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var groupID: String
    public var deckID: String
    public var title: String
    /// "Quick facts".
    public var subtitle: String
    public var details: String
    public var tags: [String]
    /// An http(s) link, or empty.
    public var link: String
    public var order: Double
    public var createdAt: Date
    public var systemFields: Data?

    public init(id: String = makeID(), groupID: String, deckID: String, draft: CardDraft, order: Double, createdAt: Date) {
        self.id = id
        self.groupID = groupID
        self.deckID = deckID
        self.title = draft.title
        self.subtitle = draft.subtitle
        self.details = draft.details
        self.tags = draft.tags
        self.link = draft.link
        self.order = order
        self.createdAt = createdAt
    }
}

/// Someone who swipes. Several people can share one phone and switch between turns.
public struct Player: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var groupID: String
    public var name: String
    /// 0–7, an index into the player colors.
    public var color: Int
    public var createdAt: Date
    public var systemFields: Data?

    public init(id: String = makeID(), groupID: String, name: String, color: Int, createdAt: Date) {
        self.id = id
        self.groupID = groupID
        self.name = name
        self.color = color
        self.createdAt = createdAt
    }

    /// The first color no one in the group has yet.
    public static func nextColor(after players: [Player]) -> Int {
        let used = Set(players.map(\.color))
        return (0..<8).first { !used.contains($0) } ?? players.count % 8
    }
}

/// One person's swipe on one card. Each is its own record, so two people
/// swiping at once never overwrite each other.
public struct Pick: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var groupID: String
    public var deckID: String
    public var cardID: String
    public var playerID: String
    public var vote: Vote
    public var updatedAt: Date
    public var systemFields: Data?

    public init(groupID: String, deckID: String, cardID: String, playerID: String, vote: Vote, updatedAt: Date) {
        self.id = Pick.id(cardID: cardID, playerID: playerID)
        self.groupID = groupID
        self.deckID = deckID
        self.cardID = cardID
        self.playerID = playerID
        self.vote = vote
        self.updatedAt = updatedAt
    }

    public static func id(cardID: String, playerID: String) -> String {
        "pick_\(cardID)_\(playerID)"
    }
}

extension Array where Element == Card {
    /// The order cards are swiped in: as added.
    public func inSwipeOrder() -> [Card] {
        sorted { a, b in
            if a.order != b.order { return a.order < b.order }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id < b.id
        }
    }
}
