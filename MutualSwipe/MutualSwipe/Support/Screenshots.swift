import Foundation
import MutualKit

/// The cloud build launches the app with `-screenshots <screen>` to photograph
/// each screen with sample decks: home, swipe, results or card. Nothing here
/// runs in normal use, and it never touches iCloud.
enum Screenshots {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var isActive: Bool {
        screen != nil
    }

    static let groupID = "group-sample"
    /// Who's swiping on the screenshot phone.
    static let meID = "sam"
    static let dateDeckID = "deck-dates"
    static let picnicCardID = "card-picnic"

    struct SampleCard {
        let id: String
        let title: String
        let subtitle: String
        let details: String
        let tags: [String]
        let alex: Vote?
        let sam: Vote?
    }

    struct SampleDeck {
        let id: String
        let title: String
        let kind: DeckKind
        let blurb: String
        /// Seconds before now it was made; newest shows first.
        let age: TimeInterval
        let cards: [SampleCard]
    }

    static let decks: [SampleDeck] = [
        SampleDeck(id: dateDeckID, title: "Date nights", kind: .dates, blurb: "Ideas for the next few Fridays", age: -3_600, cards: [
            SampleCard(id: picnicCardID, title: "Sunset picnic", subtitle: "$ · 2 hours · the park",
                       details: "Takeout, a blanket and the best view in town. Bring the speaker.",
                       tags: ["outdoors", "cheap"], alex: .love, sam: .love),
            SampleCard(id: "card-stars", title: "Stargazing drive", subtitle: "Free · late · out of town",
                       details: "Drive past the city lights, park somewhere dark, and find the planets.",
                       tags: ["outdoors"], alex: .like, sam: .love),
            SampleCard(id: "card-cooking", title: "Cooking class for two", subtitle: "$$ · 3 hours · downtown",
                       details: "Make fresh pasta together, then eat everything you made.",
                       tags: ["food", "learn"], alex: .love, sam: .nope),
            SampleCard(id: "card-comedy", title: "Comedy club", subtitle: "$$ · evening · downtown",
                       details: "Open mic night. Sit in the back row if you don't want to be picked on.",
                       tags: ["night out"], alex: .nope, sam: .like),
            SampleCard(id: "card-pottery", title: "Pottery night", subtitle: "$$ · 2 hours",
                       details: "Make a mug each and trade them when they come out of the kiln.",
                       tags: ["hands-on"], alex: .never, sam: nil),
            SampleCard(id: "card-games", title: "Board game café", subtitle: "$ · 2–3 hours",
                       details: "Hundreds of games, good coffee, and a staff member to teach you the rules.",
                       tags: ["cozy", "cheap"], alex: .like, sam: nil),
            SampleCard(id: "card-brunch", title: "Bike to brunch", subtitle: "$ · morning · 6 miles",
                       details: "Ride the river trail to the diner with the giant pancakes.",
                       tags: ["active", "morning"], alex: .like, sam: nil),
            SampleCard(id: "card-fort", title: "Living-room movie fort", subtitle: "Free · at home",
                       details: "Every pillow in the house, string lights and a double feature.",
                       tags: ["cozy", "at home"], alex: .love, sam: nil),
        ]),
        SampleDeck(id: "deck-dinners", title: "Dinners this week", kind: .recipes, blurb: "Under 45 minutes, please", age: -86_400, cards: [
            SampleCard(id: "card-curry", title: "Thai green curry", subtitle: "Thai · 35 min", details: "", tags: ["spicy"], alex: .love, sam: .like),
            SampleCard(id: "card-fajitas", title: "Sheet-pan fajitas", subtitle: "Tex-Mex · 30 min", details: "", tags: ["easy"], alex: .like, sam: .like),
            SampleCard(id: "card-risotto", title: "Mushroom risotto", subtitle: "Italian · 45 min", details: "", tags: [], alex: .nope, sam: .love),
            SampleCard(id: "card-salmon", title: "Lemon garlic salmon", subtitle: "30 min", details: "", tags: ["healthy"], alex: .like, sam: .like),
            SampleCard(id: "card-pizza", title: "Homemade pizza night", subtitle: "Italian · 40 min", details: "", tags: ["fun"], alex: .love, sam: .love),
        ]),
        SampleDeck(id: "deck-trip", title: "Long weekend away", kind: .travel, blurb: "Within a 3-hour drive", age: -3 * 86_400, cards: [
            SampleCard(id: "card-cabin", title: "Lake cabin", subtitle: "2 hours · summer", details: "", tags: ["quiet"], alex: .like, sam: nil),
            SampleCard(id: "card-crawl", title: "City food crawl", subtitle: "1 hour · any time", details: "", tags: ["food"], alex: .love, sam: nil),
            SampleCard(id: "card-springs", title: "Hike and hot springs", subtitle: "3 hours · fall", details: "", tags: ["active"], alex: .like, sam: nil),
        ]),
    ]
}
