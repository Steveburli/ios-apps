import Foundation

/// How one food has gone for one kid so far.
public struct FoodStats: Equatable {
    public var foodID: String
    public var tries: Int
    public var first: Date
    public var last: Date
    public var lastLiking: Liking
    public var loved: Int
    public var refused: Int
    public var reactions: Int
}

/// Where one allergen stands for one kid.
public enum AllergenState: String, Equatable {
    /// Never offered.
    case notStarted
    /// Offered once or twice.
    case introducing
    /// Offered three or more times, the last within a week.
    case inRotation
    /// Introduced, but more than a week since the last time.
    case due
    /// A possible reaction was logged. Talk to the pediatrician.
    case reaction

    public var title: String {
        switch self {
        case .notStarted: return "Not yet"
        case .introducing: return "Introducing"
        case .inRotation: return "In rotation"
        case .due: return "Due"
        case .reaction: return "Reaction noted"
        }
    }
}

public struct AllergenStatus: Identifiable, Equatable {
    public var allergen: Allergen
    public var state: AllergenState
    public var exposures: Int
    public var last: Date?
    public var id: String { allergen.rawValue }
}

/// Why a food is on today's "what to feed" list.
public enum SuggestionReason: Equatable {
    case allergen(Allergen)
    case new
    case tryAgain(tries: Int)
    case favorite

    public var title: String {
        switch self {
        case .allergen(let allergen): return "Keep \(allergen.title.lowercased()) in the rotation"
        case .new: return "Something new"
        case .tryAgain(let tries): return "Try again (\(tries) of ~10 tries)"
        case .favorite: return "A favorite"
        }
    }
}

public struct FoodSuggestion: Identifiable, Equatable {
    public var food: FoodItem
    public var reason: SuggestionReason
    public var id: String { food.id }

    public static func == (lhs: FoodSuggestion, rhs: FoodSuggestion) -> Bool {
        lhs.food.id == rhs.food.id && lhs.reason == rhs.reason
    }
}

public enum FoodProgress {
    /// The goal most first-foods plans aim for by the first birthday.
    public static let goal = 100

    /// Every food the kid has had, keyed by food ID.
    public static func stats(_ logs: [LogEntry], kidID: String) -> [String: FoodStats] {
        var result: [String: FoodStats] = [:]
        let meals = logs.filter { $0.kidID == kidID && $0.kind == .solids }.sorted { $0.start < $1.start }
        for meal in meals {
            for bite in meal.bites {
                var stats = result[bite.foodID] ?? FoodStats(foodID: bite.foodID, tries: 0, first: meal.start, last: meal.start,
                                                             lastLiking: bite.liking, loved: 0, refused: 0, reactions: 0)
                stats.tries += 1
                stats.last = meal.start
                stats.lastLiking = bite.liking
                if bite.liking == .loved { stats.loved += 1 }
                if bite.liking == .refused { stats.refused += 1 }
                if bite.reaction { stats.reactions += 1 }
                result[bite.foodID] = stats
            }
        }
        return result
    }

    /// How many different foods the kid has tried.
    public static func triedCount(_ logs: [LogEntry], kidID: String) -> Int {
        stats(logs, kidID: kidID).count
    }

    public static func allergens(_ logs: [LogEntry], kidID: String, now: Date) -> [AllergenStatus] {
        let all = stats(logs, kidID: kidID)
        return Allergen.allCases.map { allergen in
            let foods = all.values.filter { FoodGuide.food($0.foodID)?.allergen == allergen }
            let exposures = foods.reduce(0) { $0 + $1.tries }
            let reactions = foods.reduce(0) { $0 + $1.reactions }
            let last = foods.map { $0.last }.max()
            let state: AllergenState
            if reactions > 0 {
                state = .reaction
            } else if exposures == 0 {
                state = .notStarted
            } else if exposures < 3 {
                state = .introducing
            } else if let last, now.timeIntervalSince(last) > 7 * 86_400 {
                state = .due
            } else {
                state = .inRotation
            }
            return AllergenStatus(allergen: allergen, state: state, exposures: exposures, last: last)
        }
    }

    /// The order to start allergens in, when none has been started yet.
    public static let allergenOrder: [Allergen] = [.egg, .peanut, .milk, .wheat, .soy, .sesame, .fish, .treeNut, .shellfish]

    /// Today's "what to feed" ideas for one kid: one allergen to start or keep
    /// up, two new foods, one refused food worth another try, and one favorite.
    /// The picks rotate by day, so the list changes daily but not on every open.
    public static func suggestions(for kid: Kid, logs: [LogEntry], now: Date,
                                   calendar: Calendar = Dates.calendar) -> [FoodSuggestion] {
        let age = kid.ageMonths(on: now, calendar: calendar)
        guard age >= 6 else { return [] }
        let day = Dates.ordinal(Dates.key(now, calendar: calendar), calendar: calendar)
        let all = stats(logs, kidID: kid.id)
        let fits = FoodGuide.all.filter { $0.minMonths <= age }
        var picks: [FoodSuggestion] = []

        // One allergen: the most overdue, then one being introduced, then the next to start.
        let statuses = allergens(logs, kidID: kid.id, now: now)
        func state(_ allergen: Allergen) -> AllergenStatus? { statuses.first { $0.allergen == allergen } }
        let due = statuses.filter { $0.state == .due }.sorted { ($0.last ?? .distantPast) < ($1.last ?? .distantPast) }
        let introducing = allergenOrder.compactMap(state).filter { $0.state == .introducing }
        let notStarted = allergenOrder.compactMap(state).filter { $0.state == .notStarted }
        if let next = (due + introducing + notStarted).first {
            let options = fits.filter { $0.allergen == next.allergen }
            if !options.isEmpty {
                // Keep offering a food they've had; otherwise rotate through the options.
                let known = options.filter { all[$0.id] != nil }
                let pool = known.isEmpty ? options : known
                picks.append(FoodSuggestion(food: pool[day % pool.count], reason: .allergen(next.allergen)))
            }
        }

        // Two new foods, skipping allergens that haven't been started (they come one at a time above).
        let started = Set(statuses.filter { $0.state != .notStarted && $0.state != .reaction }.map { $0.allergen })
        let fresh = fits.filter { food in
            all[food.id] == nil && !picks.contains { $0.food.id == food.id }
                && (food.allergen == nil || started.contains(food.allergen!))
        }
        if !fresh.isEmpty {
            let first = (day * 2) % fresh.count
            picks.append(FoodSuggestion(food: fresh[first], reason: .new))
            if fresh.count > 1 {
                picks.append(FoodSuggestion(food: fresh[(first + 1) % fresh.count], reason: .new))
            }
        }

        // A refused food: it can take 10 or more tries before a kid accepts a food.
        let retry = all.values
            .filter { $0.lastLiking == .refused && $0.tries < 10 && $0.reactions == 0 }
            .sorted { $0.last < $1.last }
        if let food = retry.first, let item = FoodGuide.food(food.foodID), !picks.contains(where: { $0.food.id == item.id }) {
            picks.append(FoodSuggestion(food: item, reason: .tryAgain(tries: food.tries)))
        }

        // A favorite.
        let favorites = all.values
            .filter { $0.loved > 0 && $0.reactions == 0 }
            .sorted { ($0.loved, $0.foodID) > ($1.loved, $1.foodID) }
        if let food = favorites.first, let item = FoodGuide.food(food.foodID), !picks.contains(where: { $0.food.id == item.id }) {
            picks.append(FoodSuggestion(food: item, reason: .favorite))
        }
        return picks
    }
}
