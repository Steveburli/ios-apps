import Foundation

/// A ready-made card. Picking a starter deck copies these into a normal deck,
/// so people can edit or delete them like any other card.
public struct StarterCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Quick facts: area · price · type.
    public let facts: String
    public let about: String
    public let goodFor: String
    public let todo: String
    /// The place's own website, or empty.
    public let website: String
    /// The sub-category the preview filters by, like "Brunch" or "Weekend".
    public let section: String
    public let tags: [String]
    /// A photo from the place's website is bundled as `starter-<id>.jpg`.
    /// Sources are listed in MutualSwipe/PHOTO-SOURCES.md.
    public let hasPhoto: Bool

    init(_ id: String, _ title: String, _ facts: String, _ about: String, good: String = "", todo: String = "",
         site: String = "", section: String, tags: [String] = [], photo: Bool = false) {
        self.id = id
        self.title = title
        self.facts = facts
        self.about = about
        self.goodFor = good
        self.todo = todo
        self.website = site
        self.section = section
        self.tags = tags
        self.hasPhoto = photo
    }

    /// The bundled photo's file name, without the extension.
    public var photoName: String? { hasPhoto ? "starter-" + id : nil }

    /// The card as it's copied into a deck. "Good for" and "What to do" go in
    /// the details so they stay editable and sync like any other text.
    public var draft: CardDraft {
        var details = about
        if !goodFor.isEmpty { details += "\n\nGood for: " + goodFor }
        if !todo.isEmpty { details += "\nWhat to do: " + todo }
        return CardDraft(title: title, subtitle: facts, details: details, link: website, tags: tags)
    }
}

public struct StarterDeck: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: DeckKind
    public let blurb: String
    public let cards: [StarterCard]

    /// The sub-categories, in the order they first appear.
    public var sections: [String] {
        var seen: [String] = []
        for card in cards where !seen.contains(card.section) { seen.append(card.section) }
        return seen
    }
}

/// Mutual's built-in starter decks: Indianapolis-area places and things to do.
/// Each place was checked open, with its website, in November 2026.
public enum Starter {
    /// When every place was last checked. Shown on the card details.
    public static let lastChecked = "November 2026"

    /// The meal-categories deck. Chain a round from it into Dinners and the
    /// winner's title (say, "Pizza") narrows Dinners to cards tagged with it.
    public static let mealsID = "meals"

    public static let decks: [StarterDeck] = [meals, dinners, dates, movies, trips]

    /// The starter card a deck's card came from, matched by its website, or by
    /// its title when it has no link. Used to show the bundled photo.
    public static func match(_ card: Card) -> StarterCard? {
        let link = normalized(card.link)
        if !link.isEmpty {
            return byLink[link]
        }
        return byTitle[card.title.lowercased()]
    }

    private static let all: [StarterCard] = decks.flatMap(\.cards)

    private static let byLink: [String: StarterCard] = {
        var map: [String: StarterCard] = [:]
        for card in all where !card.website.isEmpty { map[normalized(card.website)] = map[normalized(card.website)] ?? card }
        return map
    }()

    private static let byTitle: [String: StarterCard] = {
        var map: [String: StarterCard] = [:]
        for card in all where card.hasPhoto { map[card.title.lowercased()] = card }
        return map
    }()

    /// A link without its scheme, "www." or trailing slash, lowercased.
    static func normalized(_ link: String) -> String {
        var text = link.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    // MARK: The decks

    public static let meals = StarterDeck(id: mealsID, title: "What should we eat?", kind: .restaurants,
                                   blurb: "Pick a kind of food first, then chain into Dinners", cards: [
        StarterCard("m-pizza", "Pizza", "Delivery or dine-in", "Thin, deep dish or wood-fired.", section: "Eat out"),
        StarterCard("m-mexican", "Mexican", "Tacos, burritos, queso", "Street tacos to sit-down margaritas.", section: "Eat out"),
        StarterCard("m-burgers", "Burgers", "Fries required", "Smash, pub or fancy.", section: "Eat out"),
        StarterCard("m-italian", "Italian", "Pasta night", "Red sauce, white tablecloth or somewhere in between.", section: "Eat out"),
        StarterCard("m-steak", "Steak", "Special occasion", "A proper night out.", section: "Eat out"),
        StarterCard("m-bbq", "BBQ", "Brisket, ribs, pulled pork", "Bring wet wipes.", section: "Eat out"),
        StarterCard("m-chicken", "Chicken", "Fried or grilled", "Buckets, sandwiches or wings.", section: "Eat out"),
        StarterCard("m-soul", "Soul food", "Comfort plates", "Greens, mac and cheese, cornbread.", section: "Eat out"),
        StarterCard("m-thai", "Thai", "Curry and noodles", "Pick your spice level.", section: "Eat out"),
        StarterCard("m-indian", "Indian", "Curry, naan, biryani", "Share a few dishes.", section: "Eat out"),
        StarterCard("m-pho", "Pho", "Vietnamese", "A big bowl of soup and banh mi.", section: "Eat out"),
        StarterCard("m-sushi", "Sushi", "Rolls and sashimi", "Or the hibachi grill.", section: "Eat out"),
        StarterCard("m-seafood", "Seafood", "Fish and shrimp", "Fried, grilled or raw bar.", section: "Eat out"),
        StarterCard("m-deli", "Deli", "Sandwiches", "Piled-high sandwiches and soup.", section: "Eat out"),
        StarterCard("m-brunch", "Brunch", "Breakfast any time", "Pancakes, eggs and coffee.", section: "Eat out"),
        StarterCard("m-mediterranean", "Mediterranean", "Gyros, falafel, hummus", "Light and quick.", section: "Eat out"),
        StarterCard("m-home", "Cook at home", "Free-ish", "Pick a recipe and make it together.", section: "At home"),
        StarterCard("m-leftovers", "Leftovers", "Free", "Clean out the fridge.", section: "At home"),
    ])

    public static let dinners = StarterDeck(id: "dinners", title: "Indy dinners", kind: .restaurants,
                                     blurb: "Indianapolis restaurants, tagged by kind of food", cards: [
        StarterCard("d-stelmo", "St. Elmo Steak House", "Downtown · $$$$ · Steak",
                    "Open since 1902, across from the Circle Centre mall.",
                    good: "Anniversaries, birthdays, out-of-town guests", todo: "Order the famously spicy shrimp cocktail",
                    site: "https://www.stelmos.com/", section: "Special night", tags: ["Steak"], photo: true),
        StarterCard("d-harryizzy", "Harry & Izzy's", "Downtown · $$$ · Steak",
                    "St. Elmo's more relaxed sibling, with the same shrimp cocktail.",
                    good: "A nice dinner without dressing up", todo: "Sit at the bar before a game or show",
                    site: "https://www.harryandizzys.com/", section: "Special night", tags: ["Steak"], photo: true),
        StarterCard("d-bluebeard", "Bluebeard", "Fletcher Place · $$$",
                    "Seasonal small plates in an old warehouse, with bread from the bakery next door.",
                    good: "Trying new things, sharing plates", todo: "Order a few plates for the table",
                    site: "https://bluebeardindy.com/", section: "Special night", photo: true),
        StarterCard("d-ricks", "Rick's Café Boatyard", "Eagle Creek · $$$ · Seafood",
                    "Dinner on the water at Eagle Creek Reservoir.",
                    good: "Sunsets, summer evenings", todo: "Ask for a deck table at sunset",
                    site: "https://ricksboatyard.com/", section: "Special night", tags: ["Seafood"], photo: true),
        StarterCard("d-konajacks", "Kona Jack's", "96th & Meridian · $$$ · Seafood · Sushi",
                    "Fish market, sushi bar and dinner in one.",
                    good: "Seafood lovers, sushi night", todo: "Get sushi from the bar and a fish entrée to share",
                    site: "https://jacksarebetter.net/", section: "Special night", tags: ["Seafood", "Sushi"]),
        StarterCard("d-iarias", "Iaria's Italian Restaurant", "Downtown · $$ · Italian",
                    "Family-run red-sauce classic, run by the fourth generation.",
                    good: "Comfort food, family dinners", todo: "Get the lasagna and the garlic bread",
                    site: "https://www.iariasitalianrestaurant.com/", section: "Italian & pizza", tags: ["Italian"]),
        StarterCard("d-mamacarolla", "Mama Carolla's", "Meridian-Kessler · $$ · Italian",
                    "Old-world Italian dinners in a converted house with a garden patio.",
                    good: "Date night, a cozy evening", todo: "Eat on the patio in warm weather",
                    site: "https://www.mamacarollas.com/", section: "Italian & pizza", tags: ["Italian"], photo: true),
        StarterCard("d-bazbeaux", "Bazbeaux Pizza", "Mass Ave and Broad Ripple · $$ · Pizza",
                    "Local favorite with a long topping list.",
                    good: "Groups, picky eaters", todo: "Build your own from the topping list",
                    site: "https://bazbeaux.com/", section: "Italian & pizza", tags: ["Pizza"], photo: true),
        StarterCard("d-kingdough", "King Dough", "Holy Cross · $$ · Pizza",
                    "Wood-fired pies in a small neighborhood spot.",
                    good: "A casual pizza night", todo: "Split a pie and a salad",
                    site: "https://www.kingdoughpizza.com/", section: "Italian & pizza", tags: ["Pizza"]),
        StarterCard("d-shapiros", "Shapiro's Delicatessen", "South Meridian · $ · Deli",
                    "Cafeteria-style deli open since 1905.",
                    good: "Lunch, big appetites", todo: "Corned beef on rye and a slice of cake",
                    site: "https://shapiros.com/", section: "Casual", tags: ["Deli"], photo: true),
        StarterCard("d-turchettis", "Turchetti's", "Fountain Square · $ · Deli",
                    "Butcher shop with house-made sandwiches and salami.",
                    good: "A quick lunch, picnic supplies", todo: "Grab sandwiches to go",
                    site: "https://www.turchettis.com/", section: "Casual", tags: ["Deli"], photo: true),
        StarterCard("d-eagle", "The Eagle", "Mass Ave · $$ · Chicken",
                    "Fried chicken, hot honey and bourbon in a lively food and beer hall.",
                    good: "Friends, game nights", todo: "Order the chicken with hot honey",
                    site: "https://www.eaglerestaurant.com/", section: "Casual", tags: ["Chicken"]),
        StarterCard("d-kountry", "Kountry Kitchen Soul Food Place", "College Ave · $ · Soul food",
                    "A soul-food landmark, rebuilt bigger after a 2020 fire.",
                    good: "Comfort food, Sunday dinner", todo: "Smothered pork chops and peach cobbler",
                    site: "https://kountrykitchenindy.com/", section: "Casual", tags: ["Soul food"]),
        StarterCard("d-workingman", "Workingman's Friend", "Near west side · $ · Burgers",
                    "Old-school bar with famous double smash burgers. Cash is handy.",
                    good: "Burger cravings, no-fuss nights", todo: "Order the double cheeseburger and onion rings",
                    site: "https://www.facebook.com/workingmansfriend/", section: "Casual", tags: ["Burgers"]),
        StarterCard("d-bru", "Bru Burger Bar", "Mass Ave · $$ · Burgers",
                    "Burgers, milkshakes, local beer and a big patio.",
                    good: "Groups, patio weather", todo: "Get a spiked milkshake",
                    site: "https://www.bruburgerbar.com/", section: "Casual", tags: ["Burgers"], photo: true),
        StarterCard("d-squealers", "Squealers BBQ", "Mooresville · $$ · BBQ",
                    "Smoked ribs and brisket, about 25 minutes south of downtown.",
                    good: "BBQ fans, a drive out of town", todo: "Share a rib platter",
                    site: "https://www.squealersbbq.com/", section: "Casual", tags: ["BBQ"], photo: true),
        StarterCard("d-garage", "Garage Food Hall", "Bottleworks District · $–$$",
                    "Food stalls in an old Coca-Cola garage, so everyone picks their own counter.",
                    good: "Groups who can't agree", todo: "Walk the whole hall before choosing",
                    site: "https://www.garageindy.com/", section: "Casual", tags: ["Pizza", "Mexican", "Burgers"], photo: true),
        StarterCard("d-chinita", "La Chinita Poblana", "Fountain Square · $ · Mexican",
                    "Tacos and tortas with a mix of Mexican and Asian flavors.",
                    good: "Adventurous eaters, a cheap night", todo: "Try a few different tacos",
                    site: "https://www.lachinitapoblana.com/", section: "Around the world", tags: ["Mexican"]),
        StarterCard("d-bakersfield", "Bakersfield Mass Ave", "Mass Ave · $$ · Mexican",
                    "Tacos, tequila and whiskey, with a late kitchen.",
                    good: "Late dinners, before a show", todo: "Tacos and a margarita at the bar",
                    site: "https://www.bakersfieldtacos.com/", section: "Around the world", tags: ["Mexican"], photo: true),
        StarterCard("d-siam", "Siam Square", "Fountain Square · $$ · Thai",
                    "Neighborhood Thai with a long menu.",
                    good: "Curry cravings, takeout night", todo: "Pick your spice level carefully",
                    site: "https://siamsquareindy.com/", section: "Around the world", tags: ["Thai"], photo: true),
        StarterCard("d-indiagarden", "India Garden", "Downtown · $$ · Indian",
                    "Curries, tandoori and naan near Monument Circle.",
                    good: "Sharing dishes, a lunch buffet", todo: "Order a few curries and garlic naan",
                    site: "https://www.indiagardenindy.com/", section: "Around the world", tags: ["Indian"]),
        StarterCard("d-pho54", "What The Pho", "Michigan Road · $ · Pho",
                    "Big bowls of pho and banh mi. It used to be called Pho 54.",
                    good: "Cold nights, a cheap dinner", todo: "Get the house special pho",
                    site: "https://whatthephoindy.com/", section: "Around the world", tags: ["Pho"], photo: true),
        StarterCard("d-milktooth", "Milktooth", "Fletcher Place · $$ · Brunch",
                    "Inventive brunch in an old garage. Daytime only.",
                    good: "Weekend mornings, foodies", todo: "Go early on weekends, it fills up",
                    site: "https://www.milktoothindy.com/", section: "Brunch", tags: ["Brunch"]),
        StarterCard("d-patachou", "Café Patachou", "Several locations · $ · Brunch",
                    "Big breakfasts and good coffee.",
                    good: "Easy mornings, catching up", todo: "Get the cinnamon toast",
                    site: "https://www.cafepatachou.com/", section: "Brunch", tags: ["Brunch"], photo: true),
    ])

    public static let dates = StarterDeck(id: "dates", title: "Indy date nights", kind: .dates,
                                   blurb: "Things to do in and around Indianapolis", cards: [
        StarterCard("n-newfields", "Newfields", "Art museum and gardens · $$",
                    "The art museum, gardens and Winter Lights from November to January.",
                    good: "Any season, art lovers", todo: "Walk the gardens, then the galleries",
                    site: "https://discovernewfields.org/", section: "Culture", photo: true),
        StarterCard("n-garfield", "Garfield Park Conservatory", "South side · $",
                    "Tropical greenhouse next to the sunken gardens.",
                    good: "A warm escape in winter", todo: "See the conservatory, then the sunken gardens",
                    site: "https://www.garfieldgardensconservatory.org/", section: "Culture"),
        StarterCard("n-artcenter", "Indianapolis Art Center class", "Broad Ripple · $$",
                    "Make something together: pottery, glass or painting.",
                    good: "Hands-on couples, trying something new", todo: "Book a one-night class",
                    site: "https://indyartcenter.org/", section: "Culture", photo: true),
        StarterCard("n-connerprairie", "Conner Prairie", "Fishers · $$",
                    "Living history park with seasonal evening events.",
                    good: "Fall nights, history fans", todo: "Check the events calendar for evening programs",
                    site: "https://www.connerprairie.org/", section: "Culture", photo: true),
        StarterCard("n-culturaltrail", "Cultural Trail by bike", "Downtown · $",
                    "Ride Pacers Bikeshare along the Cultural Trail and stop for a drink.",
                    good: "Nice weather, exploring downtown", todo: "Ride from Mass Ave to Fountain Square",
                    site: "https://indyculturaltrail.org/", section: "Outdoors", photo: true),
        StarterCard("n-canal", "Canal Walk paddle boat", "Downtown · $$ · warm months",
                    "Pedal the canal past the museums.",
                    good: "Summer evenings", todo: "Rent a pedal boat, then walk the canal",
                    site: "https://wheelfunrentals.com/in/indianapolis/", section: "Outdoors"),
        StarterCard("n-zoo", "Indianapolis Zoo", "White River State Park · $$",
                    "Dolphins, orangutans and the gardens next door.",
                    good: "Daytime dates, animal lovers", todo: "Catch the dolphin show",
                    site: "https://www.indianapoliszoo.com/", section: "Outdoors", photo: true),
        StarterCard("n-holliday", "Holliday Park ruins", "North side · Free",
                    "Walk the trails and sit by the ruins at sunset.",
                    good: "A free evening, photos", todo: "Walk the trails down to the river",
                    site: "https://www.hollidaypark.org/", section: "Outdoors", photo: true),
        StarterCard("n-eaglecreek", "Eagle Creek Park", "Northwest side · $",
                    "Kayak, hike or watch the sunset over the reservoir.",
                    good: "Active couples", todo: "Rent a kayak in summer",
                    site: "https://eaglecreekpark.org/", section: "Outdoors", photo: true),
        StarterCard("n-monon", "Monon Trail to Broad Ripple", "North side · Free",
                    "Walk or bike the trail, then dinner in the village.",
                    good: "A free afternoon", todo: "End with ice cream in Broad Ripple",
                    site: "https://www.indy.gov/activity/monon-trail", section: "Outdoors"),
        StarterCard("n-duckpin", "Fountain Square duckpin bowling", "Fountain Square · $",
                    "Vintage duckpin lanes in the Fountain Square Theatre Building.",
                    good: "A little competition", todo: "Bowl a few frames, then drinks on the roof",
                    site: "https://fountainsquareindy.com/", section: "Games", photo: true),
        StarterCard("n-pins", "Pins Mechanical Co.", "Bottleworks District · $ · 21+",
                    "Duckpin, pinball and a big patio.",
                    good: "Playful nights", todo: "Play a round of duckpin and some pinball",
                    site: "https://www.pinsbar.com/", section: "Games", photo: true),
        StarterCard("n-topgolf", "Topgolf", "Fishers · $$",
                    "Hit golf balls at targets with snacks.",
                    good: "Non-golfers too, cold nights in a heated bay", todo: "Book a bay for an hour",
                    site: "https://topgolf.com/us/fishers/", section: "Games", photo: true),
        StarterCard("n-jazzkitchen", "The Jazz Kitchen", "Meridian-Kessler · $$",
                    "Live jazz with dinner.",
                    good: "A grown-up night out", todo: "Book dinner seats for the early set",
                    site: "https://thejazzkitchen.com/", section: "Shows & music", photo: true),
        StarterCard("n-chatterbox", "Chatterbox Jazz Club", "Mass Ave · $",
                    "Tiny, loud and a local institution.",
                    good: "Late nights", todo: "Go after dinner on Mass Ave",
                    site: "https://www.chatterboxjazz.com/", section: "Shows & music"),
        StarterCard("n-comedysportz", "ComedySportz", "The Wit Theater, south side · $$",
                    "Improv comedy where the audience helps. Now at the Wit Theater on Shelby Street.",
                    good: "Laughing together, family-friendly shows", todo: "Shout out suggestions",
                    site: "https://www.indycomedysportz.com/", section: "Shows & music"),
        StarterCard("n-mortys", "Morty's Comedy Joint", "North side · $$",
                    "Stand-up from touring comics.",
                    good: "A night out with drinks", todo: "Check the lineup and book ahead",
                    site: "https://www.mortyscomedy.com/", section: "Shows & music", photo: true),
        StarterCard("n-irt", "Indiana Repertory Theatre", "Downtown · $$$",
                    "A play in a restored 1920s theatre.",
                    good: "Theater fans, a dressy night", todo: "Dinner downtown first",
                    site: "https://www.irtlive.com/", section: "Shows & music", photo: true),
        StarterCard("n-iso", "Indianapolis Symphony", "Hilbert Circle Theatre · $$$",
                    "The symphony on Monument Circle.",
                    good: "Special occasions", todo: "Try a pops concert",
                    site: "https://www.indianapolissymphony.org/", section: "Shows & music", photo: true),
        StarterCard("n-hifi", "HI-FI Indy", "Fountain Square · $$",
                    "Small music venue with good sight lines.",
                    good: "Live music fans", todo: "Pick a show and get there early",
                    site: "https://hifiindy.com/", section: "Shows & music", photo: true),
        StarterCard("n-sunking", "Sun King taproom", "Downtown · $",
                    "Local beer and food trucks.",
                    good: "A low-key evening", todo: "Try a flight",
                    site: "https://www.sunkingbrewing.com/", section: "Drinks", photo: true),
    ])

    public static let movies = StarterDeck(id: "movies", title: "Indy movie nights", kind: .movies,
                                    blurb: "Places to see a movie", cards: [
        StarterCard("v-livingroom", "Living Room Theaters", "Bottleworks District · $$",
                    "Dine-in recliners in the old Coca-Cola bottling plant.",
                    good: "Dinner and a movie in one", todo: "Order food to your seat",
                    site: "https://livingroomtheaters.com/", section: "Indie & dine-in"),
        StarterCard("v-kankan", "Kan-Kan Cinema and Brasserie", "Windsor Park · $$",
                    "Indie films with a bar and King Dough pizza in the building.",
                    good: "Film lovers", todo: "Eat at the bar before the film",
                    site: "https://kankanindy.com/", section: "Indie & dine-in"),
        StarterCard("v-landmark", "Landmark Keystone Art Cinema", "Keystone at the Crossing · $$",
                    "Independent and foreign films.",
                    good: "Award-season movies", todo: "Catch a weeknight showing",
                    site: "https://www.landmarktheatres.com/our-locations/x07m6-landmark-keystone-art-cinema-indianapolis/",
                    section: "Indie & dine-in"),
        StarterCard("v-imax", "IMAX at the Indiana State Museum", "White River State Park · $$",
                    "Documentaries and blockbusters on a giant screen.",
                    good: "Big movies", todo: "Book center seats",
                    site: "https://www.indianamuseum.org/", section: "Big screen", photo: true),
        StarterCard("v-georgetown", "Alamo Drafthouse Indianapolis", "Lafayette Road · $$",
                    "Dine-in theater with food and drinks brought to your seat. It replaced the old Georgetown 14.",
                    good: "Movie buffs, no talking allowed", todo: "Order a shake during the trailers",
                    site: "https://drafthouse.com/indianapolis", section: "Big screen"),
        StarterCard("v-emagine", "Emagine Noblesville", "Noblesville · $$",
                    "Big screens and reclining seats.",
                    good: "Comfortable seats, new releases", todo: "Reserve recliners ahead",
                    site: "https://www.emagine-entertainment.com/theatres/emagine-noblesville/", section: "Big screen",
                    photo: true),
        StarterCard("v-tibbs", "Tibbs Drive-In", "West side · $ · April to October",
                    "Double features from your car, on four screens since 1967.",
                    good: "Summer nights, cheap dates", todo: "Bring blankets and snacks",
                    site: "https://tibbsdriveintheatre.com/", section: "Outdoors", photo: true),
        StarterCard("v-newfieldsfilms", "Newfields Summer Nights films", "Newfields · $ · summer",
                    "Outdoor movies on the lawn.",
                    good: "Picnic dates", todo: "Bring a picnic and a blanket",
                    site: "https://discovernewfields.org/", section: "Outdoors"),
        StarterCard("v-fort", "Living-room movie fort", "At home · Free",
                    "Every pillow you own, string lights and a double feature.",
                    good: "Rainy nights, staying in", todo: "Each person picks one movie",
                    section: "At home"),
    ])

    public static let trips = StarterDeck(id: "trips", title: "Trips from Indy", kind: .travel,
                                   blurb: "Day trips and weekends, with drive times from downtown", cards: [
        StarterCard("t-browncounty", "Brown County and Nashville, IN", "1 hr · day or weekend",
                    "Fall colors, art galleries and fudge.",
                    good: "Fall weekends", todo: "Hike Brown County State Park, then shop in Nashville",
                    site: "https://browncounty.com/", section: "Day trip", photo: true),
        StarterCard("t-columbus", "Columbus, IN", "45 min · day",
                    "Modern architecture tour in a small town.",
                    good: "Design fans", todo: "Take the architecture tour",
                    site: "https://visitcolumbusindiana.com/", section: "Day trip", photo: true),
        StarterCard("t-bloomington", "Bloomington", "1 hr · day",
                    "Kirkwood Avenue and Lake Monroe.",
                    good: "A college-town day", todo: "Lunch on Kirkwood, then the lake",
                    site: "https://www.visitbloomington.com/", section: "Day trip"),
        StarterCard("t-turkeyrun", "Turkey Run State Park", "1 hr 15 min · day",
                    "Ladders, canyons and the covered bridge.",
                    good: "Hikers", todo: "Trail 3 with the ladders",
                    site: "https://www.in.gov/dnr/state-parks/parks-lakes/turkey-run-state-park/", section: "Day trip",
                    photo: true),
        StarterCard("t-shades", "Shades State Park", "1 hr 15 min · day",
                    "Quiet trails and sandstone cliffs.",
                    good: "Avoiding crowds", todo: "Hike to Devil's Punchbowl",
                    site: "https://www.in.gov/dnr/state-parks/parks-lakes/shades-state-park/", section: "Day trip",
                    photo: true),
        StarterCard("t-mccormicks", "McCormick's Creek State Park", "1 hr · day",
                    "Indiana's first state park, with a waterfall.",
                    good: "An easy hike", todo: "See the falls after a rain",
                    site: "https://www.in.gov/dnr/state-parks/parks-lakes/mccormicks-creek-state-park/", section: "Day trip",
                    photo: true),
        StarterCard("t-wolfpark", "Wolf Park, Battle Ground", "1 hr · day",
                    "A wolf sanctuary with howl nights.",
                    good: "Animal lovers", todo: "Go on a howl night",
                    site: "https://visitwolfpark.org/", section: "Day trip"),
        StarterCard("t-airforce", "National Museum of the US Air Force", "2 hr · day",
                    "Huge free museum in Dayton.",
                    good: "History and plane fans", todo: "Plan most of a day",
                    site: "https://www.nationalmuseum.af.mil/", section: "Day trip", photo: true),
        StarterCard("t-holidayworld", "Holiday World", "2 hr 45 min · day",
                    "Wooden roller coasters in Santa Claus, IN.",
                    good: "Thrill seekers, summer", todo: "Ride The Voyage",
                    site: "https://holidayworld.com/", section: "Day trip", photo: true),
        StarterCard("t-frenchlick", "French Lick and West Baden Springs", "2 hr · weekend",
                    "Grand hotels and the giant domed atrium.",
                    good: "A fancy weekend", todo: "Stay at West Baden and see the dome",
                    site: "https://www.frenchlick.com/", section: "Weekend", photo: true),
        StarterCard("t-madison", "Madison, IN and Clifty Falls", "2 hr · weekend",
                    "River town, antiques and waterfalls.",
                    good: "A slow weekend", todo: "Hike Clifty Falls, then walk Main Street",
                    site: "https://visitmadison.org/", section: "Weekend"),
        StarterCard("t-cincinnati", "Cincinnati", "1 hr 45 min · weekend",
                    "Findlay Market, the zoo and chili.",
                    good: "A city weekend", todo: "Saturday morning at Findlay Market",
                    site: "https://www.visitcincy.com/", section: "Weekend", photo: true),
        StarterCard("t-louisville", "Louisville", "2 hr · weekend",
                    "Churchill Downs and the bourbon trail.",
                    good: "Bourbon fans", todo: "Tour a distillery downtown",
                    site: "https://www.gotolouisville.com/", section: "Weekend", photo: true),
        StarterCard("t-dunes", "Indiana Dunes National Park", "2 hr 30 min · weekend",
                    "Beaches and big dunes on Lake Michigan.",
                    good: "Beach weekends", todo: "Climb the 3 Dune Challenge",
                    site: "https://www.nps.gov/indu/", section: "Weekend", photo: true),
        StarterCard("t-chicago", "Chicago", "3 hr · weekend",
                    "Museums, the lake and deep dish.",
                    good: "A big-city weekend", todo: "Architecture boat tour",
                    site: "https://www.choosechicago.com/", section: "Weekend", photo: true),
        StarterCard("t-starvedrock", "Starved Rock State Park", "3 hr 15 min · weekend",
                    "Canyons and waterfalls in Illinois.",
                    good: "Hikers", todo: "Go in spring when the falls run",
                    site: "https://www.starvedrockstatepark.org/", section: "Weekend", photo: true),
        StarterCard("t-lexington", "Lexington horse country", "3 hr · weekend",
                    "Horse farms and Keeneland.",
                    good: "Spring or fall race meets", todo: "Watch morning workouts at Keeneland",
                    site: "https://www.visitlex.com/", section: "Weekend", photo: true),
        StarterCard("t-mammoth", "Mammoth Cave National Park", "3 hr 30 min · weekend",
                    "The world's longest known cave system.",
                    good: "Adventurers", todo: "Book a cave tour ahead",
                    site: "https://www.nps.gov/maca/", section: "Weekend", photo: true),
        StarterCard("t-stlouis", "St. Louis", "4 hr · weekend",
                    "The Arch, the zoo and toasted ravioli.",
                    good: "A city weekend with free museums", todo: "Ride to the top of the Arch",
                    site: "https://explorestlouis.com/", section: "Weekend", photo: true),
    ])
}
