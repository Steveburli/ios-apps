import Foundation

/// The nine major US food allergens.
public enum Allergen: String, Codable, CaseIterable, Identifiable {
    case egg, peanut, milk, wheat, soy, sesame, fish, treeNut, shellfish

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .egg: return "Egg"
        case .peanut: return "Peanut"
        case .milk: return "Dairy"
        case .wheat: return "Wheat"
        case .soy: return "Soy"
        case .sesame: return "Sesame"
        case .fish: return "Fish"
        case .treeNut: return "Tree nuts"
        case .shellfish: return "Shellfish"
        }
    }

    public var emoji: String {
        switch self {
        case .egg: return "🥚"
        case .peanut: return "🥜"
        case .milk: return "🧀"
        case .wheat: return "🌾"
        case .soy: return "🫘"
        case .sesame: return "🫓"
        case .fish: return "🐟"
        case .treeNut: return "🌰"
        case .shellfish: return "🦐"
        }
    }
}

public enum FoodCategory: String, Codable, CaseIterable, Identifiable {
    case fruit, vegetable, protein, grain, dairy, fat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fruit: return "Fruits"
        case .vegetable: return "Vegetables"
        case .protein: return "Proteins"
        case .grain: return "Grains"
        case .dairy: return "Dairy"
        case .fat: return "Fats & spreads"
        }
    }
}

/// How much care a food needs for choking: low, take care, or high (always
/// change its shape or texture before serving).
public enum ChokeRisk: Int, Codable, Comparable {
    case low = 0, medium, high

    public static func < (lhs: ChokeRisk, rhs: ChokeRisk) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .low: return "Low choking risk"
        case .medium: return "Take care"
        case .high: return "Common choking hazard"
        }
    }
}

/// One food in the guide, with how to serve it at each stage.
public struct FoodItem: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var emoji: String
    public var category: FoodCategory
    public var allergen: Allergen?
    public var choke: ChokeRisk
    /// The youngest age to offer it at all.
    public var minMonths: Int
    /// 6–8 months: palmar grasp, big pieces or soft textures.
    public var early: String
    /// 9–11 months: pincer grasp, small soft pieces.
    public var middle: String
    /// 12 months and up.
    public var toddler: String
    public var tip: String

    public init(_ id: String, _ name: String, _ emoji: String, _ category: FoodCategory, allergen: Allergen? = nil,
                choke: ChokeRisk = .low, minMonths: Int = 6, early: String, middle: String, toddler: String, tip: String = "") {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.category = category
        self.allergen = allergen
        self.choke = choke
        self.minMonths = minMonths
        self.early = early
        self.middle = middle
        self.toddler = toddler
        self.tip = tip
    }

    /// The serving advice for a kid this many months old.
    public func howToServe(ageMonths: Int) -> String {
        if ageMonths < 9 { return early }
        if ageMonths < 12 { return middle }
        return toddler
    }

    public static func stageTitle(ageMonths: Int) -> String {
        if ageMonths < 9 { return "6–8 months" }
        if ageMonths < 12 { return "9–11 months" }
        return "12 months +"
    }
}

/// Foods to hold off on, and until when.
public struct HoldOff: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var untilMonths: Int
    public var why: String
}

/// The app's own first-foods guide. General guidance written for this app,
/// not medical advice; the Food tab says to check with the pediatrician,
/// especially before allergens for a baby with severe eczema or a known allergy.
public enum FoodGuide {
    public static func food(_ id: String) -> FoodItem? {
        index[id]
    }

    private static let index: [String: FoodItem] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func foods(with allergen: Allergen) -> [FoodItem] {
        all.filter { $0.allergen == allergen }
    }

    public static let holdOffs: [HoldOff] = [
        HoldOff(id: "honey", title: "Honey (even baked in)", untilMonths: 12,
                why: "It can carry the spores that cause infant botulism."),
        HoldOff(id: "cowsmilk", title: "Cow's milk as a drink", untilMonths: 12,
                why: "It crowds out breast milk or formula and is low in iron. Yogurt, cheese and milk in cooking are fine earlier."),
        HoldOff(id: "juice", title: "Juice", untilMonths: 12,
                why: "Whole fruit is better. After 1, keep juice small, if at all."),
        HoldOff(id: "sugar", title: "Added sugar", untilMonths: 24,
                why: "Sweets crowd out the foods they need and set up a sweet tooth."),
        HoldOff(id: "salt", title: "Salty foods", untilMonths: 12,
                why: "Little kidneys need little salt. Cook without it and add salt to the grown-up portions."),
        HoldOff(id: "wholenuts", title: "Whole nuts, popcorn, hard candy, gum", untilMonths: 48,
                why: "Common choking hazards under 4. Offer nuts ground or as a thin spread."),
        HoldOff(id: "grapes", title: "Whole grapes, cherry tomatoes, hot dog coins", untilMonths: 48,
                why: "Round and firm: they can block an airway. Quarter them lengthwise."),
        HoldOff(id: "mercury", title: "High-mercury fish", untilMonths: 216,
                why: "Skip shark, swordfish, king mackerel, tilefish and bigeye tuna. Salmon, cod and sardines are great."),
        HoldOff(id: "raw", title: "Raw or unpasteurized foods", untilMonths: 60,
                why: "Unpasteurized milk and cheese, raw eggs, raw sprouts and undercooked meat carry more germs."),
    ]

    public static let all: [FoodItem] = [
        // Fruits
        FoodItem("avocado", "Avocado", "🥑", .fruit,
                 early: "Thick spears of ripe avocado, or mashed on a preloaded spoon. Leave a strip of skin on for grip.",
                 middle: "Bite-size soft cubes, or mashed on toast strips.",
                 toddler: "Cubes, slices or guacamole.",
                 tip: "Roll slippery spears in ground flax or hemp seeds for grip."),
        FoodItem("banana", "Banana", "🍌", .fruit,
                 early: "Half a banana with the bottom peel left on as a handle.",
                 middle: "Bite-size pieces, or thick slices cut in half.",
                 toddler: "Slices or a whole peeled banana."),
        FoodItem("blueberry", "Blueberries", "🫐", .fruit, choke: .high,
                 early: "Squash each berry flat between your fingers, or mash into yogurt.",
                 middle: "Flattened or halved.",
                 toddler: "Halve big ones until 4; small soft ones can be whole once they chew well."),
        FoodItem("strawberry", "Strawberries", "🍓", .fruit,
                 early: "A very large whole ripe berry to munch, or mashed.",
                 middle: "Thin slices or small pieces.",
                 toddler: "Quartered or sliced."),
        FoodItem("raspberry", "Raspberries", "🍇", .fruit,
                 early: "Flattened, or mashed into oatmeal.",
                 middle: "Whole or halved: they squish easily.",
                 toddler: "Whole."),
        FoodItem("mango", "Mango", "🥭", .fruit,
                 early: "The pit with some fruit on it to gnaw, or thick ripe spears.",
                 middle: "Bite-size soft pieces.",
                 toddler: "Slices or cubes."),
        FoodItem("pear", "Pear", "🍐", .fruit, choke: .medium,
                 early: "Very ripe pear in large wedges with skin off, or steamed until soft.",
                 middle: "Small soft pieces of ripe or cooked pear.",
                 toddler: "Thin slices of ripe pear.",
                 tip: "If it isn't soft enough to squish between your fingers, cook it."),
        FoodItem("apple", "Apple", "🍎", .fruit, choke: .high,
                 early: "Cooked apple spears or applesauce. Raw apple only grated.",
                 middle: "Cooked pieces or grated raw.",
                 toddler: "Very thin raw slices or grated; cook it if pieces come off in chunks.",
                 tip: "Raw apple breaks into hard chunks: a classic choking food under 4."),
        FoodItem("peach", "Peach", "🍑", .fruit,
                 early: "A ripe pitted half or thick wedges, skin on for grip.",
                 middle: "Small soft pieces.",
                 toddler: "Slices."),
        FoodItem("watermelon", "Watermelon", "🍉", .fruit,
                 early: "Finger-size seedless spears.",
                 middle: "Bite-size seedless pieces.",
                 toddler: "Slices or cubes."),
        FoodItem("orange", "Orange", "🍊", .fruit,
                 early: "A large wedge to suck on, seeds out.",
                 middle: "Segments with the membrane removed, cut into pieces.",
                 toddler: "Segments, cut if large.",
                 tip: "Citrus can cause a harmless rash around the mouth."),
        FoodItem("kiwi", "Kiwi", "🥝", .fruit,
                 early: "Peeled ripe kiwi in thick spears or halves.",
                 middle: "Small pieces.",
                 toddler: "Slices or pieces.",
                 tip: "Can cause a mild mouth rash; true kiwi allergy is less common."),
        FoodItem("grape", "Grapes", "🍇", .fruit, choke: .high, minMonths: 6,
                 early: "Quartered lengthwise and flattened, or skip for now.",
                 middle: "Quartered lengthwise.",
                 toddler: "Quartered lengthwise until at least 4.",
                 tip: "A whole grape is the right size and shape to block an airway."),
        FoodItem("cherry", "Cherries", "🍒", .fruit, choke: .high,
                 early: "Pitted and quartered, or mashed.",
                 middle: "Pitted and quartered.",
                 toddler: "Pitted and halved or quartered."),
        FoodItem("plum", "Plum", "🟣", .fruit,
                 early: "A ripe pitted half to munch.",
                 middle: "Small soft pieces.",
                 toddler: "Slices."),
        FoodItem("pineapple", "Pineapple", "🍍", .fruit,
                 early: "Thin, ripe spears or the core to gnaw (supervised).",
                 middle: "Small soft pieces.",
                 toddler: "Bite-size pieces.",
                 tip: "Acidic: a mouth rash is common and harmless."),

        // Vegetables
        FoodItem("sweetpotato", "Sweet potato", "🍠", .vegetable,
                 early: "Roasted wedges, soft enough to squish, or mashed.",
                 middle: "Soft cubes or mash.",
                 toddler: "Wedges, cubes or mash."),
        FoodItem("broccoli", "Broccoli", "🥦", .vegetable,
                 early: "Steamed large florets with a long stem as a handle.",
                 middle: "Small steamed florets.",
                 toddler: "Steamed or roasted florets."),
        FoodItem("carrot", "Carrot", "🥕", .vegetable, choke: .high,
                 early: "Steamed or roasted spears, soft all the way through.",
                 middle: "Soft cooked coins cut in half, or grated raw.",
                 toddler: "Cooked pieces or grated raw. Hold off on raw sticks until they chew well.",
                 tip: "Raw carrot is hard and a common choking food."),
        FoodItem("peas", "Peas", "🟢", .vegetable, choke: .medium,
                 early: "Cooked and smashed, on a preloaded spoon or spread on toast.",
                 middle: "Cooked and lightly flattened: great pincer practice.",
                 toddler: "Cooked whole peas."),
        FoodItem("greenbeans", "Green beans", "🫛", .vegetable,
                 early: "Whole steamed beans, soft enough to squish.",
                 middle: "Steamed, cut into small pieces.",
                 toddler: "Steamed or roasted pieces."),
        FoodItem("butternut", "Butternut squash", "🎃", .vegetable,
                 early: "Roasted soft wedges or mash.",
                 middle: "Soft cubes.",
                 toddler: "Cubes, mash or soup."),
        FoodItem("zucchini", "Zucchini", "🥒", .vegetable,
                 early: "Roasted or steamed spears, skin on.",
                 middle: "Soft half-moons or small pieces.",
                 toddler: "Slices or pieces."),
        FoodItem("cauliflower", "Cauliflower", "🥬", .vegetable,
                 early: "Steamed large florets.",
                 middle: "Small steamed florets.",
                 toddler: "Roasted or steamed florets."),
        FoodItem("cucumber", "Cucumber", "🥒", .vegetable, choke: .medium,
                 early: "Grated, or a long peeled spear to gnaw with you right there.",
                 middle: "Very thin slices or grated.",
                 toddler: "Thin slices or sticks."),
        FoodItem("tomato", "Tomato", "🍅", .vegetable, choke: .medium,
                 early: "Large ripe wedges with skin, or a big slice.",
                 middle: "Small pieces; cherry tomatoes quartered.",
                 toddler: "Cherry tomatoes quartered until 4."),
        FoodItem("bellpepper", "Bell pepper", "🫑", .vegetable, choke: .medium,
                 early: "Roasted soft strips, skin peeled off.",
                 middle: "Small roasted pieces, or a big raw strip to gnaw.",
                 toddler: "Thin raw strips or cooked pieces."),
        FoodItem("spinach", "Spinach", "🍃", .vegetable,
                 early: "Cooked and chopped into eggs, pasta or purees.",
                 middle: "Chopped and cooked into dishes.",
                 toddler: "Cooked or chopped raw in dishes.",
                 tip: "Raw leaves can stick to the roof of the mouth; chop them."),
        FoodItem("corn", "Corn", "🌽", .vegetable, choke: .medium,
                 early: "A short piece of cob to gnaw, or kernels mashed.",
                 middle: "Cooked kernels, lightly smashed.",
                 toddler: "Kernels or corn on the cob."),
        FoodItem("potato", "Potato", "🥔", .vegetable,
                 early: "Soft roasted wedges or mashed.",
                 middle: "Soft cubes or mash.",
                 toddler: "Any soft-cooked shape."),
        FoodItem("mushroom", "Mushrooms", "🍄", .vegetable,
                 early: "Large sautéed slices.",
                 middle: "Finely chopped and cooked.",
                 toddler: "Sliced and cooked."),
        FoodItem("beet", "Beets", "🟥", .vegetable,
                 early: "Roasted soft wedges.",
                 middle: "Small soft cubes.",
                 toddler: "Cubes or slices.",
                 tip: "Red diapers after beets are normal."),

        // Proteins
        FoodItem("egg", "Egg", "🥚", .protein, allergen: .egg,
                 early: "Well-cooked: omelet strips, or hard-boiled and mashed or quartered.",
                 middle: "Scrambled pieces or chopped hard-boiled egg.",
                 toddler: "Any well-cooked way.",
                 tip: "Start with a small amount early in the day, then offer it a few times a week."),
        FoodItem("peanut", "Peanut butter", "🥜", .protein, allergen: .peanut,
                 early: "Smooth peanut butter thinned with water, breast milk or yogurt, or a thin smear on toast.",
                 middle: "Thinly spread on toast strips or stirred into oatmeal.",
                 toddler: "Thinly spread. Never globs or whole peanuts under 4.",
                 tip: "Early, regular peanut lowers the chance of peanut allergy. Babies with severe eczema or egg allergy: ask the pediatrician first."),
        FoodItem("almond", "Almond butter", "🌰", .protein, allergen: .treeNut,
                 early: "Thinned smooth almond butter, or finely ground almonds in oatmeal.",
                 middle: "Thin spread on toast strips.",
                 toddler: "Thin spread or finely ground. No whole nuts under 4."),
        FoodItem("cashew", "Cashew butter", "🌰", .protein, allergen: .treeNut,
                 early: "Thinned smooth cashew butter stirred into yogurt or puree.",
                 middle: "Thin spread on toast strips.",
                 toddler: "Thin spread. No whole nuts under 4."),
        FoodItem("salmon", "Salmon", "🐟", .protein, allergen: .fish,
                 early: "Flaked, deboned, in large pieces or salmon cakes.",
                 middle: "Small deboned flakes.",
                 toddler: "Flakes or patties.",
                 tip: "Low in mercury and rich in omega-3s."),
        FoodItem("cod", "Cod", "🐠", .protein, allergen: .fish,
                 early: "Flaked and deboned.",
                 middle: "Small flakes.",
                 toddler: "Flakes, fish cakes or sticks."),
        FoodItem("shrimp", "Shrimp", "🦐", .protein, allergen: .shellfish, choke: .medium,
                 early: "Finely minced, mixed into rice or patties.",
                 middle: "Chopped small.",
                 toddler: "Cut into small pieces."),
        FoodItem("chicken", "Chicken", "🍗", .protein,
                 early: "Moist thigh meat in large strips, or shredded, or ground into soft patties.",
                 middle: "Shredded or finely chopped moist meat.",
                 toddler: "Small pieces.",
                 tip: "Dark meat stays softer and has more iron."),
        FoodItem("beef", "Beef", "🥩", .protein, choke: .medium,
                 early: "Slow-cooked strips to suck on, or soft meatballs and patties.",
                 middle: "Ground beef or shredded slow-cooked meat.",
                 toddler: "Small tender pieces.",
                 tip: "A top source of iron, which babies need more of from 6 months."),
        FoodItem("turkey", "Turkey", "🦃", .protein,
                 early: "Soft ground-turkey meatballs or patties.",
                 middle: "Crumbled or shredded.",
                 toddler: "Small pieces."),
        FoodItem("pork", "Pork", "🐖", .protein,
                 early: "Slow-cooked, shredded or in big tender strips.",
                 middle: "Shredded.",
                 toddler: "Small tender pieces."),
        FoodItem("tofu", "Tofu", "⬜", .protein, allergen: .soy,
                 early: "Firm tofu in finger-size strips, baked or pan-fried soft.",
                 middle: "Small cubes or crumbled.",
                 toddler: "Cubes."),
        FoodItem("edamame", "Edamame", "🫛", .protein, allergen: .soy, choke: .medium,
                 early: "Shelled, cooked and smashed.",
                 middle: "Shelled and flattened.",
                 toddler: "Shelled, halved until they chew well."),
        FoodItem("blackbeans", "Black beans", "⚫", .protein,
                 early: "Mashed, or flattened beans to rake up.",
                 middle: "Flattened beans.",
                 toddler: "Whole soft beans."),
        FoodItem("lentils", "Lentils", "🟤", .protein,
                 early: "Well-cooked and thick, on a preloaded spoon or in patties.",
                 middle: "Thick dal or lentil patties.",
                 toddler: "Soups, dal or patties."),
        FoodItem("chickpeas", "Chickpeas / hummus", "🧆", .protein, allergen: .sesame,
                 early: "Hummus (with tahini) on toast strips or a spoon; whole chickpeas smashed.",
                 middle: "Smashed chickpeas or hummus.",
                 toddler: "Halved chickpeas or hummus.",
                 tip: "Tahini in hummus is an easy way to keep sesame in the rotation."),
        FoodItem("tahini", "Tahini", "🫓", .fat, allergen: .sesame,
                 early: "Thinned and stirred into yogurt, oatmeal or purees.",
                 middle: "Thin spread on toast strips.",
                 toddler: "Spread, dip or dressing."),

        // Grains
        FoodItem("oats", "Oatmeal", "🥣", .grain,
                 early: "Thick oatmeal on a preloaded spoon, or baked into soft oat fingers.",
                 middle: "Oatmeal or soft oat bars.",
                 toddler: "Oatmeal, overnight oats or muffins."),
        FoodItem("toast", "Toast", "🍞", .grain, allergen: .wheat,
                 early: "Lightly toasted strips with a thin spread.",
                 middle: "Small squares with a spread.",
                 toddler: "Squares or halves.",
                 tip: "Toasting keeps bread from turning into a gummy ball."),
        FoodItem("pasta", "Pasta", "🍝", .grain, allergen: .wheat,
                 early: "Big shapes cooked soft: rigatoni, fusilli, lasagna strips.",
                 middle: "Small shapes or cut noodles.",
                 toddler: "Any shape."),
        FoodItem("pancake", "Pancakes", "🥞", .grain, allergen: .wheat,
                 early: "Soft strips, no syrup or added sugar.",
                 middle: "Small pieces.",
                 toddler: "Pieces or rolled up.",
                 tip: "Banana-and-egg pancakes cover two foods at once."),
        FoodItem("rice", "Rice", "🍚", .grain,
                 early: "Sticky rice pressed into small balls.",
                 middle: "Rice balls or loose rice to rake up.",
                 toddler: "Any way.",
                 tip: "Rice holds more arsenic than other grains: rotate with oats, quinoa and wheat."),
        FoodItem("quinoa", "Quinoa", "🌾", .grain,
                 early: "Cooked soft and clumped into patties, or stirred into yogurt.",
                 middle: "Loose or in patties.",
                 toddler: "Any way."),
        FoodItem("barley", "Barley", "🌾", .grain,
                 early: "Soft-cooked and mashed into purees or soups.",
                 middle: "Soft grains in soups or bowls.",
                 toddler: "Soups and bowls."),

        // Dairy
        FoodItem("yogurt", "Yogurt", "🥛", .dairy, allergen: .milk,
                 early: "Plain whole-milk yogurt on a preloaded spoon.",
                 middle: "Plain yogurt, maybe with mashed fruit.",
                 toddler: "Plain yogurt; sweeten with fruit, not sugar."),
        FoodItem("cheese", "Cheese", "🧀", .dairy, allergen: .milk, choke: .medium,
                 early: "Pasteurized, low-salt cheese in thin slices or shredded and melted.",
                 middle: "Shredded or thin small pieces.",
                 toddler: "Thin slices or shreds. Avoid hard cubes until they chew well.",
                 tip: "Swiss, mozzarella and ricotta are lower in salt."),
        FoodItem("ricotta", "Ricotta", "🥛", .dairy, allergen: .milk,
                 early: "Whole-milk pasteurized ricotta on a spoon or toast.",
                 middle: "Spread or stirred into pasta.",
                 toddler: "Any way."),
        FoodItem("cottagecheese", "Cottage cheese", "🥛", .dairy, allergen: .milk,
                 early: "Whole-milk, pasteurized, on a spoon.",
                 middle: "By itself or mixed with fruit.",
                 toddler: "Any way.",
                 tip: "Saltier than most cheeses; keep portions small."),
        FoodItem("milk", "Cow's milk (drink)", "🥛", .dairy, allergen: .milk, minMonths: 12,
                 early: "Not as a drink before 12 months. Fine in cooking.",
                 middle: "Not as a drink before 12 months. Fine in cooking.",
                 toddler: "Whole milk in an open cup, around 16–24 oz a day at most."),

        // Fats and spreads
        FoodItem("oliveoil", "Olive oil", "🫒", .fat,
                 early: "Drizzle on vegetables or mix into purees.",
                 middle: "Cook with it.",
                 toddler: "Cook with it."),
        FoodItem("butter", "Butter", "🧈", .fat, allergen: .milk,
                 early: "A little melted on vegetables or toast.",
                 middle: "On toast or vegetables.",
                 toddler: "On anything."),
    ]
}
