import Foundation

public enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .snack: return "Snack"
        case .dinner: return "Dinner"
        }
    }
}

public struct PlannedMeal: Identifiable, Equatable {
    public var slot: MealSlot
    public var foodIDs: [String]
    public var id: String { slot.rawValue }
}

public struct PlannedDay: Identifiable, Equatable {
    public var day: String
    public var meals: [PlannedMeal]
    public var id: String { day }
}

/// A week of meals for one kid that keeps every started allergen in the
/// rotation twice a week, starts one new allergen, and works in new foods.
public enum MealPlanner {
    /// The meals for a kid this age: one or two meals at 6–8 months, three at
    /// 9–11, three plus a snack from 12 months.
    public static func slots(ageMonths: Int) -> [MealSlot] {
        if ageMonths < 6 { return [] }
        if ageMonths < 9 { return [.breakfast, .dinner] }
        if ageMonths < 12 { return [.breakfast, .lunch, .dinner] }
        return [.breakfast, .lunch, .snack, .dinner]
    }

    public static func week(for kid: Kid, logs: [LogEntry], start: String, seed: Int = 0, now: Date,
                            calendar: Calendar = Dates.calendar) -> [PlannedDay] {
        let age = kid.ageMonths(on: now, calendar: calendar)
        let slots = MealPlanner.slots(ageMonths: age)
        guard !slots.isEmpty else { return [] }
        let stats = FoodProgress.stats(logs, kidID: kid.id)
        let statuses = FoodProgress.allergens(logs, kidID: kid.id, now: now)
        let blocked = Set(stats.values.filter { $0.reactions > 0 }.map { $0.foodID })
        let reacted = Set(statuses.filter { $0.state == .reaction }.map { $0.allergen })
        let fits = FoodGuide.all.filter { $0.minMonths <= age && !blocked.contains($0.id) && $0.id != "milk"
            && ($0.allergen == nil || !reacted.contains($0.allergen!)) }

        // Allergens to keep up, and the one to start this week.
        let started = statuses.filter { $0.state != .notStarted && $0.state != .reaction }.map { $0.allergen }
        let toStart = FoodProgress.allergenOrder.first { allergen in
            statuses.first { $0.allergen == allergen }?.state == .notStarted
        }
        func pick(_ list: [FoodItem], _ index: Int) -> FoodItem? {
            list.isEmpty ? nil : list[((index % list.count) + list.count) % list.count]
        }
        let mains = fits.filter { ($0.category == .protein || $0.category == .grain || $0.category == .dairy) && $0.allergen == nil }
        let produce = fits.filter { $0.category == .fruit || $0.category == .vegetable }
        let fresh = fits.filter { stats[$0.id] == nil && $0.allergen == nil }

        var days: [PlannedDay] = []
        for offset in 0..<7 {
            let day = Dates.addDays(start, offset, calendar: calendar)
            var meals: [PlannedMeal] = []
            for (slotIndex, slot) in slots.enumerated() {
                let n = seed * 31 + offset * 7 + slotIndex * 3
                var foods: [FoodItem] = []
                if slot == .snack {
                    if let fruit = pick(produce.filter { $0.category == .fruit }, n) { foods.append(fruit) }
                } else {
                    if let main = pick(mains, n) { foods.append(main) }
                    if let side = pick(produce, n + 5) { foods.append(side) }
                }
                meals.append(PlannedMeal(slot: slot, foodIDs: foods.map { $0.id }))
            }
            days.append(PlannedDay(day: day, meals: meals))
        }

        // Each started allergen twice: spread over the week, at breakfast or lunch.
        var placements: [(Allergen, Int)] = []
        for (index, allergen) in started.enumerated() {
            placements.append((allergen, (index * 2 + seed) % 7))
            placements.append((allergen, (index * 2 + seed + 3) % 7))
        }
        // A new allergen: three mornings in a row from the first day, early in the day.
        if let toStart { for offset in 0..<3 { placements.append((toStart, offset)) } }
        for (index, placement) in placements.enumerated() {
            let options = fits.filter { $0.allergen == placement.0 }
            let known = options.filter { stats[$0.id] != nil }
            guard let food = pick(known.isEmpty ? options : known, seed + index) else { continue }
            let mealIndex = placement.0 == toStart ? 0 : index % min(2, days[placement.1].meals.count)
            if !days[placement.1].meals[mealIndex].foodIDs.contains(food.id) {
                days[placement.1].meals[mealIndex].foodIDs.append(food.id)
            }
        }

        // Three new foods across the week, at dinner.
        for index in 0..<min(3, fresh.count) {
            let dayIndex = (index * 2 + 1) % 7
            if let food = pick(fresh, seed * 3 + index), let last = days[dayIndex].meals.indices.last {
                if !days[dayIndex].meals[last].foodIDs.contains(food.id) { days[dayIndex].meals[last].foodIDs.append(food.id) }
            }
        }
        return days
    }

    /// Every food in the plan once, grouped by category, for the grocery list.
    public static func groceries(_ plan: [PlannedDay]) -> [(category: FoodCategory, foods: [FoodItem])] {
        var seen = Set<String>()
        var foods: [FoodItem] = []
        for day in plan { for meal in day.meals { for id in meal.foodIDs where !seen.contains(id) {
            seen.insert(id)
            if let food = FoodGuide.food(id) { foods.append(food) }
        } } }
        return FoodCategory.allCases.compactMap { category -> (category: FoodCategory, foods: [FoodItem])? in
            let list = foods.filter { $0.category == category }.sorted { $0.name < $1.name }
            return list.isEmpty ? nil : (category, list)
        }
    }

    /// How many times each allergen appears in the plan.
    public static func allergenCounts(_ plan: [PlannedDay]) -> [Allergen: Int] {
        var counts: [Allergen: Int] = [:]
        for day in plan { for meal in day.meals { for id in meal.foodIDs {
            if let allergen = FoodGuide.food(id)?.allergen { counts[allergen, default: 0] += 1 }
        } } }
        return counts
    }
}

/// A simple recipe that covers several first foods at once.
public struct Recipe: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var emoji: String
    public var minMonths: Int
    public var minutes: Int
    public var foodIDs: [String]
    public var ingredients: [String]
    public var steps: [String]
    public var tip: String
}

public enum RecipeBook {
    public static func recipe(_ id: String) -> Recipe? {
        all.first { $0.id == id }
    }

    /// Recipes a kid this age can have, ones using foods they haven't tried first.
    public static func forKid(ageMonths: Int, tried: Set<String>) -> [Recipe] {
        all.filter { $0.minMonths <= ageMonths }
            .sorted { lhs, rhs in
                let l = lhs.foodIDs.filter { !tried.contains($0) }.count
                let r = rhs.foodIDs.filter { !tried.contains($0) }.count
                return l != r ? l > r : lhs.title < rhs.title
            }
    }

    public static let all: [Recipe] = [
        Recipe(id: "banana-pancakes", title: "Banana egg pancakes", emoji: "🥞", minMonths: 6, minutes: 15,
               foodIDs: ["banana", "egg", "oats"],
               ingredients: ["1 ripe banana", "2 eggs", "¼ cup rolled oats, blended fine"],
               steps: ["Mash the banana and whisk in the eggs and oats.", "Cook small pancakes in a buttered pan, 2 minutes a side.", "Cut into strips for babies, pieces for toddlers."],
               tip: "Egg and wheat-free; freeze extras between parchment."),
        Recipe(id: "salmon-cakes", title: "Salmon sweet potato cakes", emoji: "🐟", minMonths: 6, minutes: 30,
               foodIDs: ["salmon", "sweetpotato", "egg"],
               ingredients: ["1 cup cooked flaked salmon (bones out)", "1 cup mashed sweet potato", "1 egg"],
               steps: ["Mix everything and shape into small patties.", "Bake at 400°F for 18–20 minutes, flipping halfway.", "Cool and serve whole for babies to hold, or in pieces."],
               tip: "Fish and egg together: a good way to keep two allergens going."),
        Recipe(id: "pb-oatmeal", title: "Peanut butter oatmeal", emoji: "🥣", minMonths: 6, minutes: 10,
               foodIDs: ["oats", "peanut", "banana"],
               ingredients: ["⅓ cup oats", "⅔ cup water or milk", "1 tsp smooth peanut butter", "Mashed banana"],
               steps: ["Cook the oats until thick.", "Stir in the peanut butter so it melts in completely.", "Top with banana and let it cool."],
               tip: "Melted into oatmeal is a safe way to serve peanut: no sticky globs."),
        Recipe(id: "yogurt-bowl", title: "Berry yogurt bowl", emoji: "🍓", minMonths: 6, minutes: 5,
               foodIDs: ["yogurt", "raspberry", "blueberry", "tahini"],
               ingredients: ["Plain whole-milk yogurt", "Mashed raspberries", "Smashed blueberries", "½ tsp tahini"],
               steps: ["Swirl the tahini into the yogurt.", "Top with the mashed berries.", "Preload a spoon for babies."],
               tip: "Dairy and sesame in one bowl."),
        Recipe(id: "lentil-patties", title: "Lentil veggie patties", emoji: "🟤", minMonths: 6, minutes: 30,
               foodIDs: ["lentils", "carrot", "egg", "oats"],
               ingredients: ["1 cup cooked lentils", "½ cup grated carrot", "1 egg", "¼ cup oats"],
               steps: ["Mash the lentils and mix in the rest.", "Shape into finger-length logs.", "Bake at 375°F for 20 minutes."],
               tip: "Iron-rich; the logs are easy for babies to hold."),
        Recipe(id: "tofu-fingers", title: "Crispy tofu fingers", emoji: "⬜", minMonths: 6, minutes: 25,
               foodIDs: ["tofu", "oliveoil"],
               ingredients: ["Firm tofu", "Olive oil"],
               steps: ["Press the tofu dry and cut into finger-size strips.", "Toss with a little oil.", "Bake at 400°F for 20 minutes, until golden but still soft inside."],
               tip: "Soy in a form babies can hold."),
        Recipe(id: "chicken-meatballs", title: "Chicken broccoli meatballs", emoji: "🍗", minMonths: 6, minutes: 30,
               foodIDs: ["chicken", "broccoli", "egg", "cheese"],
               ingredients: ["1 lb ground chicken (thigh)", "1 cup finely chopped steamed broccoli", "1 egg", "¼ cup shredded mozzarella"],
               steps: ["Mix and roll into soft, golf-ball-size meatballs.", "Bake at 375°F for 20 minutes.", "Squish a little for babies; quarter for older kids."],
               tip: "Broccoli hidden in a favorite works on picky eaters too."),
        Recipe(id: "hummus-toast", title: "Hummus toast strips", emoji: "🧆", minMonths: 6, minutes: 5,
               foodIDs: ["chickpeas", "toast", "avocado"],
               ingredients: ["Toast", "Hummus", "Mashed avocado"],
               steps: ["Toast lightly and cut into strips.", "Spread thinly with hummus or avocado."],
               tip: "Sesame (tahini) and wheat in one easy snack."),
        Recipe(id: "mac-peas", title: "Mac and cheese with peas", emoji: "🧀", minMonths: 9, minutes: 20,
               foodIDs: ["pasta", "cheese", "peas", "butter"],
               ingredients: ["1 cup small pasta", "½ cup shredded cheese", "½ cup peas", "1 tbsp butter", "Splash of milk"],
               steps: ["Cook the pasta and peas together until soft.", "Drain, then stir in butter, milk and cheese until melted."],
               tip: "No salt needed: the cheese brings plenty."),
        Recipe(id: "beef-sweetpotato", title: "Slow cooker beef and sweet potato", emoji: "🥩", minMonths: 6, minutes: 360,
               foodIDs: ["beef", "sweetpotato", "carrot"],
               ingredients: ["1 lb chuck roast", "2 sweet potatoes", "3 carrots", "Low-salt broth"],
               steps: ["Put everything in a slow cooker on low for 6–8 hours.", "Shred the beef; serve big pieces for babies to suck on.", "Mash or cut the vegetables by age."],
               tip: "Fall-apart beef is the easiest red meat for babies, and full of iron."),
        Recipe(id: "shrimp-rice", title: "Shrimp fried rice", emoji: "🦐", minMonths: 9, minutes: 20,
               foodIDs: ["shrimp", "rice", "egg", "peas", "carrot"],
               ingredients: ["1 cup cooked rice", "4 shrimp, minced", "1 egg", "Peas and diced carrot"],
               steps: ["Scramble the egg and set aside.", "Cook the vegetables until soft, add shrimp until pink.", "Stir in the rice and egg; no soy sauce for babies (salt)."],
               tip: "Shellfish minced finely and mixed in."),
        Recipe(id: "almond-muffins", title: "Almond banana muffins", emoji: "🧁", minMonths: 6, minutes: 30,
               foodIDs: ["almond", "banana", "egg", "oats"],
               ingredients: ["2 bananas", "2 eggs", "¼ cup almond butter", "1 cup oat flour", "1 tsp baking powder"],
               steps: ["Mash the bananas; whisk in eggs and almond butter.", "Stir in oat flour and baking powder.", "Bake mini muffins at 350°F for 15 minutes."],
               tip: "Tree nuts and egg; no added sugar."),
    ]
}

/// A grown-up dinner and how to adapt it for each kid.
public struct FamilyDinner: Identifiable, Hashable {
    public var id: String
    public var title: String
    public var emoji: String
    /// Guide foods in the dinner.
    public var foodIDs: [String]
    /// What else is in it, and what to hold back for the little ones.
    public var tips: [String]
}

public enum FamilyDinners {
    public static let all: [FamilyDinner] = [
        FamilyDinner(id: "tacos", title: "Taco night", emoji: "🌮", foodIDs: ["beef", "blackbeans", "avocado", "cheese", "tomato"],
                     tips: ["Season the kids' meat before adding salty taco seasoning.", "Serve the fillings separately instead of a hard shell."]),
        FamilyDinner(id: "spaghetti", title: "Spaghetti and meatballs", emoji: "🍝", foodIDs: ["pasta", "beef", "tomato", "cheese"],
                     tips: ["Use big pasta shapes for babies.", "Make meatballs soft and squishable."]),
        FamilyDinner(id: "salmon", title: "Salmon, rice and broccoli", emoji: "🐟", foodIDs: ["salmon", "rice", "broccoli"],
                     tips: ["Check the salmon for bones.", "Steam the broccoli a little longer for the baby."]),
        FamilyDinner(id: "stirfry", title: "Chicken stir-fry", emoji: "🥢", foodIDs: ["chicken", "bellpepper", "broccoli", "rice"],
                     tips: ["Pull the kids' portion before adding soy sauce.", "Cut chicken into strips for babies, small pieces for toddlers."]),
        FamilyDinner(id: "pizza", title: "Homemade pizza", emoji: "🍕", foodIDs: ["toast", "cheese", "tomato", "mushroom"],
                     tips: ["Cut into thin strips for babies.", "Go light on salty toppings like pepperoni."]),
        FamilyDinner(id: "breakfast", title: "Breakfast for dinner", emoji: "🍳", foodIDs: ["egg", "pancake", "strawberry", "yogurt"],
                     tips: ["Skip syrup for the baby; mashed fruit works instead.", "Scrambled eggs cut into small pieces for toddlers."]),
        FamilyDinner(id: "soup", title: "Chicken soup", emoji: "🍲", foodIDs: ["chicken", "carrot", "potato", "pasta"],
                     tips: ["Strain the pieces out for babies and serve them soft.", "Use low-salt broth."]),
        FamilyDinner(id: "burgers", title: "Burgers and sweet potato fries", emoji: "🍔", foodIDs: ["beef", "sweetpotato", "cheese", "cucumber"],
                     tips: ["Make a small soft patty for the baby, cut into strips.", "Bake the fries instead of frying."]),
        FamilyDinner(id: "curry", title: "Lentil curry", emoji: "🍛", foodIDs: ["lentils", "rice", "spinach", "yogurt"],
                     tips: ["Mild spices are great for babies; hold back the chili heat.", "Thicken the baby's portion so it stays on the spoon."]),
        FamilyDinner(id: "roast", title: "Roast chicken and vegetables", emoji: "🍗", foodIDs: ["chicken", "potato", "carrot", "greenbeans"],
                     tips: ["Dark meat stays softer for babies.", "Roast the vegetables until soft all the way through."]),
    ]

    public struct Adaptation: Identifiable, Equatable {
        public var food: FoodItem
        public var howToServe: String
        /// "New", "Allergen", "Hold off", or "".
        public var flag: String
        public var id: String { food.id }

        public static func == (lhs: Adaptation, rhs: Adaptation) -> Bool {
            lhs.food.id == rhs.food.id && lhs.howToServe == rhs.howToServe && lhs.flag == rhs.flag
        }
    }

    /// How to serve each part of the dinner to a kid this age.
    public static func adapt(_ dinner: FamilyDinner, ageMonths: Int, tried: Set<String>) -> [Adaptation] {
        dinner.foodIDs.compactMap { FoodGuide.food($0) }.map { food -> Adaptation in
            let flag: String
            if food.minMonths > ageMonths { flag = "Hold off" }
            else if !tried.contains(food.id) && food.allergen != nil { flag = "New allergen" }
            else if !tried.contains(food.id) { flag = "New" }
            else { flag = "" }
            return Adaptation(food: food, howToServe: food.howToServe(ageMonths: ageMonths), flag: flag)
        }
    }
}

/// Picky-eater view of the food log.
public enum PickyEater {
    public struct LearningFood: Identifiable, Equatable {
        public var food: FoodItem
        public var tries: Int
        public var id: String { food.id }

        public static func == (lhs: LearningFood, rhs: LearningFood) -> Bool {
            lhs.food.id == rhs.food.id && lhs.tries == rhs.tries
        }
    }

    /// The exposures it can take before a kid accepts a food.
    public static let goal = 10

    /// Foods they reliably eat: loved at least once, or liked twice, and not refused last time.
    public static func safeFoods(_ logs: [LogEntry], kidID: String) -> [FoodItem] {
        FoodProgress.stats(logs, kidID: kidID).values
            .filter { ($0.loved > 0 || $0.tries - $0.refused >= 2) && $0.lastLiking != .refused && $0.lastLiking != .meh && $0.reactions == 0 }
            .compactMap { FoodGuide.food($0.foodID) }
            .sorted { $0.name < $1.name }
    }

    /// Foods still being learned: refused or "meh" last time, with tries so far.
    public static func learningFoods(_ logs: [LogEntry], kidID: String) -> [LearningFood] {
        FoodProgress.stats(logs, kidID: kidID).values
            .filter { ($0.lastLiking == .refused || $0.lastLiking == .meh) && $0.reactions == 0 }
            .compactMap { stats in FoodGuide.food(stats.foodID).map { LearningFood(food: $0, tries: stats.tries) } }
            .sorted { $0.tries != $1.tries ? $0.tries > $1.tries : $0.food.name < $1.food.name }
    }
}
