import Foundation

/// "Plan something new": a guided journey that ends in a deck. One person
/// answers what they're planning, a short survey and the vibe, swipes on
/// broad categories (museums, hikes, live music…), and Mutual fills a deck
/// with specific places from the liked categories. The group then swipes
/// that deck like any other, so nothing new syncs.
public enum Journey {

    // MARK: Step 1: the basics

    public enum Plan: String, CaseIterable, Identifiable, Codable, Sendable {
        case nightOut, date, dinner, dayOut, weekend

        public var id: Self { self }

        public var title: String {
            switch self {
            case .nightOut: return "A night out"
            case .date: return "A date"
            case .dinner: return "Where to eat"
            case .dayOut: return "A day out"
            case .weekend: return "A weekend"
            }
        }

        public var detail: String {
            switch self {
            case .nightOut: return "Shows, music, games, drinks"
            case .date: return "Something for the two of you"
            case .dinner: return "Pick a kind of food, then a place"
            case .dayOut: return "Museums, parks, day trips"
            case .weekend: return "Bigger plans and getaways"
            }
        }

        public var symbol: String {
            switch self {
            case .nightOut: return "moon.stars.fill"
            case .date: return "heart.fill"
            case .dinner: return "fork.knife"
            case .dayOut: return "sun.max.fill"
            case .weekend: return "suitcase.fill"
            }
        }

        public var kind: DeckKind {
            switch self {
            case .date: return .dates
            case .dinner: return .restaurants
            case .weekend: return .travel
            case .nightOut, .dayOut: return .other
            }
        }

        /// The noun used in the deck's title, like "Tonight: night out".
        var noun: String {
            switch self {
            case .nightOut: return "night out"
            case .date: return "date"
            case .dinner: return "dinner"
            case .dayOut: return "day out"
            case .weekend: return "weekend plans"
            }
        }
    }

    public enum Crowd: String, CaseIterable, Identifiable, Codable, Sendable {
        case two, friends, family

        public var id: Self { self }

        public var title: String {
            switch self {
            case .two: return "Just the two of us"
            case .friends: return "Friends"
            case .family: return "Family with kids"
            }
        }

        public var symbol: String {
            switch self {
            case .two: return "person.2.fill"
            case .friends: return "person.3.fill"
            case .family: return "figure.and.child.holdinghands"
            }
        }
    }

    // MARK: Step 2: the survey

    public enum Budget: String, CaseIterable, Identifiable, Codable, Sendable {
        case cheap, middle, splurge, any

        public var id: Self { self }

        public var title: String {
            switch self {
            case .cheap: return "Keep it cheap"
            case .middle: return "Somewhere in the middle"
            case .splurge: return "Treat ourselves"
            case .any: return "Doesn’t matter"
            }
        }

        public var symbol: String {
            switch self {
            case .cheap: return "dollarsign"
            case .middle: return "dollarsign.circle"
            case .splurge: return "sparkles"
            case .any: return "infinity"
            }
        }

        /// The most dollar signs a place can show.
        public var most: Int {
            switch self {
            case .cheap: return 1
            case .middle: return 2
            case .splurge, .any: return 4
            }
        }
    }

    public enum Distance: String, CaseIterable, Identifiable, Codable, Sendable {
        case close, city, drive

        public var id: Self { self }

        public var title: String {
            switch self {
            case .close: return "Close by"
            case .city: return "Anywhere around town"
            case .drive: return "Worth a drive"
            }
        }

        public var detail: String {
            switch self {
            case .close: return "About 10 minutes"
            case .city: return "Up to about half an hour"
            case .drive: return "Day trips and getaways too"
            }
        }

        public var symbol: String {
            switch self {
            case .close: return "figure.walk"
            case .city: return "car.fill"
            case .drive: return "road.lanes"
            }
        }

        /// How far Apple Maps looks, in meters.
        public var searchRadius: Double {
            switch self {
            case .close: return 8_000
            case .city: return 30_000
            case .drive: return 60_000
            }
        }
    }

    public enum When: String, CaseIterable, Identifiable, Codable, Sendable {
        case tonight, weekend, soon

        public var id: Self { self }

        public var title: String {
            switch self {
            case .tonight: return "Tonight"
            case .weekend: return "This weekend"
            case .soon: return "Sometime soon"
            }
        }

        public var symbol: String {
            switch self {
            case .tonight: return "clock.fill"
            case .weekend: return "calendar"
            case .soon: return "calendar.badge.plus"
            }
        }
    }

    /// Things to leave out.
    public enum Avoid: String, CaseIterable, Identifiable, Codable, Sendable {
        case drinking, late, crowds, outdoors

        public var id: Self { self }

        public var title: String {
            switch self {
            case .drinking: return "Drinking"
            case .late: return "Late nights"
            case .crowds: return "Big crowds"
            case .outdoors: return "Being outside"
            }
        }

        public var symbol: String {
            switch self {
            case .drinking: return "wineglass"
            case .late: return "moon.zzz"
            case .crowds: return "person.3.sequence"
            case .outdoors: return "cloud.rain"
            }
        }
    }

    // MARK: Step 3: the vibe

    public enum Vibe: String, CaseIterable, Identifiable, Codable, Sendable {
        case chill, adventurous, fancy, social, cozy, artsy, active

        public var id: Self { self }

        public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

        public var symbol: String {
            switch self {
            case .chill: return "leaf.fill"
            case .adventurous: return "mountain.2.fill"
            case .fancy: return "sparkles"
            case .social: return "person.3.fill"
            case .cozy: return "cup.and.saucer.fill"
            case .artsy: return "paintpalette.fill"
            case .active: return "figure.run"
            }
        }
    }

    /// Everything the planner answered.
    public struct Answers: Equatable, Codable, Sendable {
        public var plan: Plan = .nightOut
        public var crowd: Crowd = .two
        public var budget: Budget = .any
        public var distance: Distance = .city
        public var when: When = .tonight
        public var avoid: Set<Avoid> = []
        public var vibes: Set<Vibe> = []

        public init(plan: Plan = .nightOut, crowd: Crowd = .two, budget: Budget = .any, distance: Distance = .city,
                    when: When = .tonight, avoid: Set<Avoid> = [], vibes: Set<Vibe> = []) {
            self.plan = plan
            self.crowd = crowd
            self.budget = budget
            self.distance = distance
            self.when = when
            self.avoid = avoid
            self.vibes = vibes
        }
    }

    // MARK: Step 4: categories

    public struct Category: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let blurb: String
        public let symbol: String
        let plans: Set<Plan>
        let vibes: Set<Vibe>
        /// What this category involves, matched against Avoid.
        let involves: Set<Avoid>
        let kids: Bool
        /// Only when they'll make a drive.
        let trip: Bool
        /// Only when it isn't tonight.
        let needsNotice: Bool
        /// Ready-made Indianapolis cards, by starter card ID.
        public let starterIDs: [String]
        /// A starter tag that picks its cards from Indy dinners, for food categories.
        let dinnerTag: String?
        /// What to search Apple Maps for. Empty means Maps has nothing to add.
        public let mapsQueries: [String]

        init(_ id: String, _ title: String, _ blurb: String, symbol: String, plans: Set<Plan>, vibes: Set<Vibe>,
             involves: Set<Avoid> = [], kids: Bool = true, trip: Bool = false, needsNotice: Bool = false,
             starter: [String] = [], dinnerTag: String? = nil, maps: [String] = []) {
            self.id = id
            self.title = title
            self.blurb = blurb
            self.symbol = symbol
            self.plans = plans
            self.vibes = vibes
            self.involves = involves
            self.kids = kids
            self.trip = trip
            self.needsNotice = needsNotice
            self.starterIDs = starter
            self.dinnerTag = dinnerTag
            self.mapsQueries = maps
        }
    }

    private static let outings: Set<Plan> = [.nightOut, .date, .dayOut, .weekend]

    /// The broad things to do, for every plan except dinner.
    public static let activities: [Category] = [
        Category("dinner", "Dinner out", "A proper sit-down meal", symbol: "fork.knife",
                 plans: [.nightOut, .date, .weekend], vibes: [.fancy, .social, .cozy],
                 starter: Starter.dinners.cards.filter { $0.section != "Brunch" }.map(\.id), maps: ["restaurant"]),
        Category("brunch", "Brunch and coffee", "A slow morning", symbol: "cup.and.saucer.fill",
                 plans: [.date, .dayOut, .weekend], vibes: [.chill, .cozy],
                 starter: ["d-milktooth", "d-patachou"], maps: ["brunch", "coffee shop"]),
        Category("museums", "Museums and art", "Galleries, history, hands-on", symbol: "building.columns.fill",
                 plans: [.date, .dayOut, .weekend], vibes: [.artsy, .chill],
                 starter: ["n-newfields", "n-artcenter", "n-connerprairie", "t-airforce"], maps: ["museum", "art gallery"]),
        Category("hiking", "Hikes and trails", "Get some fresh air", symbol: "figure.hiking",
                 plans: [.date, .dayOut, .weekend], vibes: [.active, .adventurous, .chill], involves: [.outdoors],
                 starter: ["n-holliday", "n-eaglecreek", "n-monon", "t-turkeyrun", "t-shades", "t-mccormicks"],
                 maps: ["hiking trail", "nature preserve"]),
        Category("parks", "Parks and gardens", "Wander somewhere pretty", symbol: "leaf.fill",
                 plans: [.date, .dayOut, .weekend], vibes: [.chill, .cozy], involves: [.outdoors],
                 starter: ["n-garfield", "n-culturaltrail", "n-canal"], maps: ["park", "botanical garden"]),
        Category("animals", "Zoos and animals", "Say hi to some critters", symbol: "pawprint.fill",
                 plans: [.date, .dayOut, .weekend], vibes: [.adventurous, .chill], involves: [.outdoors, .crowds],
                 starter: ["n-zoo", "t-wolfpark"], maps: ["zoo", "aquarium"]),
        Category("movies", "Movies", "Big screen or dine-in", symbol: "film.fill",
                 plans: [.nightOut, .date, .dayOut, .weekend], vibes: [.chill, .cozy],
                 starter: Starter.movies.cards.filter { $0.id != "v-fort" }.map(\.id), maps: ["movie theater"]),
        Category("music", "Live music", "Jazz, bands, the symphony", symbol: "music.mic",
                 plans: [.nightOut, .date, .weekend], vibes: [.social, .fancy, .artsy], involves: [.late, .crowds],
                 kids: false, starter: ["n-jazzkitchen", "n-chatterbox", "n-hifi", "n-iso"], maps: ["live music venue"]),
        Category("shows", "Comedy and theater", "Laugh or be moved", symbol: "theatermasks.fill",
                 plans: [.nightOut, .date, .weekend], vibes: [.social, .artsy, .fancy], involves: [.late],
                 kids: false, starter: ["n-comedysportz", "n-mortys", "n-irt"], maps: ["comedy club", "theater"]),
        Category("games", "Games and bowling", "Bowling, arcades, golf", symbol: "gamecontroller.fill",
                 plans: [.nightOut, .date, .dayOut, .weekend], vibes: [.social, .active, .adventurous],
                 starter: ["n-duckpin", "n-pins", "n-topgolf"], maps: ["bowling alley", "arcade", "mini golf"]),
        Category("bars", "Bars and breweries", "A drink or two out", symbol: "wineglass.fill",
                 plans: [.nightOut, .date, .weekend], vibes: [.social], involves: [.drinking, .late],
                 kids: false, starter: ["n-sunking", "n-pins"], maps: ["brewery", "cocktail bar"]),
        Category("daytrips", "Day trips", "Small towns and state parks", symbol: "car.fill",
                 plans: [.date, .dayOut, .weekend], vibes: [.adventurous, .active, .chill], trip: true,
                 starter: Starter.trips.cards.filter { $0.section == "Day trip" }.map(\.id)),
        Category("getaways", "Weekend getaways", "Pack a bag", symbol: "suitcase.fill",
                 plans: [.weekend], vibes: [.adventurous, .fancy, .social], trip: true, needsNotice: true,
                 starter: Starter.trips.cards.filter { $0.section == "Weekend" }.map(\.id)),
        Category("stayin", "Stay in", "A cozy night at home", symbol: "sofa.fill",
                 plans: [.nightOut, .date], vibes: [.cozy, .chill],
                 starter: ["v-fort", "m-home"]),
    ]

    /// Kinds of food, for the dinner plan: the "What should we eat?" cards,
    /// each filled from Indy dinners tagged with it.
    public static let foods: [Category] = Starter.meals.cards.filter { $0.section == "Eat out" }.map { meal in
        Category("food-" + meal.title.lowercased().replacingOccurrences(of: " ", with: "-"), meal.title, meal.facts,
                 symbol: "fork.knife", plans: [.dinner], vibes: [], dinnerTag: meal.title,
                 maps: [meal.title + " restaurant"])
    }

    /// The categories to swipe on, best vibe match first. Categories that
    /// clash with the answers are left out.
    public static func categories(for answers: Answers) -> [Category] {
        if answers.plan == .dinner {
            return foods
        }
        let fits = activities.filter { category in
            category.plans.contains(answers.plan)
                && category.involves.isDisjoint(with: answers.avoid)
                && (category.kids || answers.crowd != .family)
                && (!category.trip || answers.distance == .drive)
                && (!category.needsNotice || answers.when != .tonight)
                && !(category.id == "stayin" && answers.crowd == .friends && answers.plan == .date)
        }
        guard !answers.vibes.isEmpty else { return fits }
        // A stable sort: more shared vibes first, then the list's own order.
        return fits.enumerated().sorted { a, b in
            let left = a.element.vibes.intersection(answers.vibes).count
            let right = b.element.vibes.intersection(answers.vibes).count
            return left != right ? left > right : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Step 5: specific places

    /// One place or idea for the final deck.
    public struct Place: Identifiable, Equatable, Sendable {
        public enum Source: String, Sendable { case indy, maps }

        public let id: String
        public let categoryID: String
        public let source: Source
        public let draft: CardDraft
        /// The bundled photo for an Indy place.
        public let photoName: String?

        public init(id: String, categoryID: String, source: Source, draft: CardDraft, photoName: String? = nil) {
            self.id = id
            self.categoryID = categoryID
            self.source = source
            self.draft = draft
            self.photoName = photoName
        }
    }

    /// The most places a category adds to the deck.
    public static let perCategory = 8

    /// Ready-made Indianapolis places for the liked categories that fit the
    /// answers. Each card is tagged with its category's name.
    public static func indyPlaces(for liked: [Category], answers: Answers) -> [Place] {
        var seen = Set<String>()
        var places: [Place] = []
        for category in liked {
            let cards: [StarterCard]
            if let tag = category.dinnerTag {
                cards = Starter.dinners.cards.filter { $0.tags.contains(tag) }
            } else {
                cards = category.starterIDs.compactMap(starterByID)
            }
            var added = 0
            for card in cards where added < perCategory && fits(card, answers) && seen.insert(card.id).inserted {
                var draft = card.draft
                if !draft.tags.contains(category.title) { draft.tags.insert(category.title, at: 0) }
                places.append(Place(id: card.id, categoryID: category.id, source: .indy, draft: draft, photoName: card.photoName))
                added += 1
            }
        }
        return places
    }

    /// How many more places Apple Maps should find for a category.
    public static func mapsWanted(for category: Category, indyCount: Int) -> Int {
        category.mapsQueries.isEmpty ? 0 : max(0, min(5, perCategory - indyCount))
    }

    /// Whether a ready-made card suits the answers: price, drive time, 21+.
    static func fits(_ card: StarterCard, _ answers: Answers) -> Bool {
        if let price = price(of: card.facts), price > answers.budget.most { return false }
        if card.id.hasPrefix("t-") && answers.distance != .drive { return false }
        if card.facts.contains("21+") && (answers.crowd == .family || answers.avoid.contains(.drinking)) { return false }
        return true
    }

    /// The dollar signs in a card's quick facts: "Free" is 0, "$$" is 2,
    /// "$–$$" is 1. Nil when it doesn't say.
    public static func price(of facts: String) -> Int? {
        for part in facts.components(separatedBy: "·") {
            let text = part.trimmingCharacters(in: .whitespaces)
            if text.lowercased().hasPrefix("free") { return 0 }
            if text.hasPrefix("$") { return text.prefix { $0 == "$" }.count }
        }
        return nil
    }

    private static let starterByID: (String) -> StarterCard? = {
        let all = Dictionary(Starter.decks.flatMap(\.cards).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return { all[$0] }
    }()

    // MARK: The deck it makes

    public static func deckTitle(for answers: Answers) -> String {
        "\(answers.when.title): \(answers.plan.noun)"
    }

    /// A one-line summary of the answers, shown under the deck's title.
    public static func deckBlurb(for answers: Answers) -> String {
        var parts = [answers.crowd.title]
        if answers.budget != .any { parts.append(answers.budget.title.lowercased()) }
        parts.append(answers.distance.title.lowercased())
        let vibes = Vibe.allCases.filter(answers.vibes.contains).map(\.title)
        if !vibes.isEmpty { parts.append(vibes.joined(separator: ", ").lowercased()) }
        return "Planned in Mutual · " + parts.joined(separator: " · ")
    }

    /// Whether a deck was made by the journey, from its blurb.
    public static func isPlanned(blurb: String) -> Bool {
        blurb.hasPrefix("Planned in Mutual")
    }
}
