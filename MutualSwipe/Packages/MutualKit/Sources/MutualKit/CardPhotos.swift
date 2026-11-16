import Foundation

/// One photo someone added to a card, so the card shows what a place feels
/// like: the outside, the inside, a busy night, the seating, a popular dish.
///
/// Each photo is its own record (like a Pick), so two people adding photos
/// to the same card at once never overwrite each other. A photo never
/// changes after it's added; removing it deletes the record. The image itself
/// lives in a file named `<id>.jpg` on the phone and as an asset in iCloud.
public struct CardPhoto: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var groupID: String
    public var deckID: String
    public var cardID: String
    /// Photos show in this order, oldest first.
    public var order: Double
    /// The name of the person who added it, or empty.
    public var addedBy: String
    public var createdAt: Date
    public var systemFields: Data?

    public init(id: String = "photo_" + makeID(), groupID: String, deckID: String, cardID: String,
                order: Double, addedBy: String, createdAt: Date) {
        self.id = id
        self.groupID = groupID
        self.deckID = deckID
        self.cardID = cardID
        self.order = order
        self.addedBy = addedBy
        self.createdAt = createdAt
    }
}

public enum CardPhotos {
    /// The most photos one card holds: room for 4 or 5 of the place plus a dish or two.
    public static let limit = 6

    /// Photos are shrunk so their longest side is at most this many pixels,
    /// which keeps each one around 200 KB and syncing quick.
    public static let maxPixels: Double = 1_280

    /// The tip shown next to "Add photos".
    public static let tip = "Pick 4 or 5 photos that show the vibe: the outside, the inside, a busy night, the seating. Then add the most popular dishes from the reviews."

    /// A card's photos in the order they show.
    public static func sorted(_ photos: [CardPhoto]) -> [CardPhoto] {
        photos.sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    /// How many more photos fit on a card that already has `count`.
    public static func room(after count: Int) -> Int {
        max(0, limit - count)
    }

    /// The size to shrink a photo to, keeping its shape. Small photos stay as they are.
    public static func fittedSize(width: Double, height: Double) -> (width: Double, height: Double) {
        let longest = max(width, height)
        guard longest > maxPixels, longest > 0 else { return (width, height) }
        let scale = maxPixels / longest
        return ((width * scale).rounded(), (height * scale).rounded())
    }

    /// A Google Maps search for the card's place. On an iPhone with Google
    /// Maps it opens the app, where the place's Photos tab has the "Vibe"
    /// and "Food & Drink" groups.
    public static func mapsURL(for card: Card) -> URL? {
        let place = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return nil }
        var parts = URLComponents(string: "https://www.google.com/maps/search/")!
        parts.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: place)]
        return parts.url
    }
}
