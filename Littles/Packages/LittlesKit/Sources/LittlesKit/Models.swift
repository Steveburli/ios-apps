import Foundation

// Every saved type decodes field by field with defaults, so files saved by an
// older build keep loading after fields are added.

public struct Kid: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    /// `yyyy-MM-dd`.
    public var birthday: String
    /// Index into the app's kid palette.
    public var color: Int
    public var emoji: String
    /// "boy", "girl" or "" (unknown). Only used to pick the growth percentile table.
    public var sex: String

    public init(id: String = UUID().uuidString, name: String, birthday: String, color: Int, emoji: String = "", sex: String = "") {
        self.id = id
        self.name = name
        self.birthday = birthday
        self.color = color
        self.emoji = emoji
        self.sex = sex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Kid"
        birthday = try c.decodeIfPresent(String.self, forKey: .birthday) ?? ""
        color = try c.decodeIfPresent(Int.self, forKey: .color) ?? 0
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        sex = try c.decodeIfPresent(String.self, forKey: .sex) ?? ""
    }

    public func ageMonths(on date: Date, calendar: Calendar = Dates.calendar) -> Int {
        Age.months(birthday: birthday, on: date, calendar: calendar)
    }

    public func ageLabel(on date: Date, calendar: Calendar = Dates.calendar) -> String {
        Age.label(birthday: birthday, on: date, calendar: calendar)
    }

    public var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

/// What one log entry records.
public enum LogKind: String, Codable, CaseIterable, Identifiable {
    case bottle, nursing, pump, diaper, sleep, solids, potty, meds, temperature, growth, bath, note
    case symptom, tooth, brush, screen, outside, first, quote

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bottle: return "Bottle"
        case .nursing: return "Nurse"
        case .pump: return "Pump"
        case .diaper: return "Diaper"
        case .sleep: return "Sleep"
        case .solids: return "Meal"
        case .potty: return "Potty"
        case .meds: return "Medicine"
        case .temperature: return "Temp"
        case .growth: return "Growth"
        case .bath: return "Bath"
        case .note: return "Note"
        case .symptom: return "Sick"
        case .tooth: return "Tooth"
        case .brush: return "Brush"
        case .screen: return "Screen"
        case .outside: return "Outside"
        case .first: return "First"
        case .quote: return "Quote"
        }
    }

    public var emoji: String {
        switch self {
        case .bottle: return "🍼"
        case .nursing: return "🤱"
        case .pump: return "🥛"
        case .diaper: return "🧷"
        case .sleep: return "😴"
        case .solids: return "🥑"
        case .potty: return "🚽"
        case .meds: return "💊"
        case .temperature: return "🌡️"
        case .growth: return "📏"
        case .bath: return "🛁"
        case .note: return "📝"
        case .symptom: return "🤒"
        case .tooth: return "🦷"
        case .brush: return "🪥"
        case .screen: return "📺"
        case .outside: return "🌳"
        case .first: return "⭐️"
        case .quote: return "💬"
        }
    }

    /// Kinds that run as a timer: the entry has no end until it's stopped.
    public var isTimed: Bool {
        self == .sleep || self == .nursing
    }

    /// Kinds logged as a number of minutes (screen time, time outside).
    public var isMinutes: Bool {
        self == .screen || self == .outside
    }

    /// Kinds kept as memories (firsts, quotes) on the Grow tab.
    public var isMemory: Bool {
        self == .first || self == .quote
    }

    /// Kinds that count as a feed for "last fed" and the feed gap.
    public var isFeed: Bool {
        self == .bottle || self == .nursing
    }
}

public enum MilkType: String, Codable, CaseIterable, Identifiable {
    case formula, breastMilk, wholeMilk, water, other
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .formula: return "Formula"
        case .breastMilk: return "Breast milk"
        case .wholeMilk: return "Whole milk"
        case .water: return "Water"
        case .other: return "Other"
        }
    }
}

public enum Side: String, Codable, CaseIterable, Identifiable {
    case left, right, both
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .both: return "Both"
        }
    }
    public var letter: String {
        switch self {
        case .left: return "L"
        case .right: return "R"
        case .both: return "L+R"
        }
    }
}

public enum DiaperKind: String, Codable, CaseIterable, Identifiable {
    case wet, dirty, mixed, dry
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .wet: return "Wet"
        case .dirty: return "Dirty"
        case .mixed: return "Both"
        case .dry: return "Dry"
        }
    }
    public var isWet: Bool { self == .wet || self == .mixed }
    public var isDirty: Bool { self == .dirty || self == .mixed }
}

public enum PottyKind: String, Codable, CaseIterable, Identifiable {
    case pee, poop, both, tried, accident
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .pee: return "Pee"
        case .poop: return "Poop"
        case .both: return "Both"
        case .tried: return "Tried"
        case .accident: return "Accident"
        }
    }
    public var isSuccess: Bool { self == .pee || self == .poop || self == .both }
}

/// How a food went over.
public enum Liking: String, Codable, CaseIterable, Identifiable {
    case loved, liked, meh, refused
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .loved: return "Loved it"
        case .liked: return "Liked it"
        case .meh: return "Meh"
        case .refused: return "Refused"
        }
    }
    public var emoji: String {
        switch self {
        case .loved: return "😍"
        case .liked: return "🙂"
        case .meh: return "😐"
        case .refused: return "🙅"
        }
    }
}

/// One food in a meal: which food, how it went, and any reaction.
public struct FoodBite: Codable, Hashable, Identifiable {
    public var foodID: String
    public var liking: Liking
    /// A possible reaction (rash, hives, vomiting, swelling).
    public var reaction: Bool
    public var id: String { foodID }

    public init(foodID: String, liking: Liking = .liked, reaction: Bool = false) {
        self.foodID = foodID
        self.liking = liking
        self.reaction = reaction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foodID = try c.decodeIfPresent(String.self, forKey: .foodID) ?? ""
        liking = (try? c.decodeIfPresent(Liking.self, forKey: .liking)) ?? .liked
        reaction = try c.decodeIfPresent(Bool.self, forKey: .reaction) ?? false
    }
}

/// One thing that happened to one kid: a bottle, a diaper, a nap, a meal.
/// Fields that don't apply to a kind stay nil or empty.
public struct LogEntry: Codable, Identifiable, Hashable {
    public var id: String
    public var kidID: String
    public var kind: LogKind
    public var start: Date
    /// Timed kinds (sleep, nursing) have no end while they run.
    public var end: Date?
    public var amountOz: Double?
    public var milk: MilkType?
    public var side: Side?
    public var diaper: DiaperKind?
    public var potty: PottyKind?
    public var bites: [FoodBite]
    public var medicine: String
    public var dose: String
    public var temperatureF: Double?
    public var weightLb: Double?
    public var heightIn: Double?
    public var headIn: Double?
    public var note: String
    /// A photo's file name in Application Support/photos; empty for none.
    public var photo: String
    /// Symptoms for a sick-day entry ("Cough", "Runny nose").
    public var symptoms: [String]
    /// Minutes for screen time and time outside.
    public var minutes: Int?
    /// When it was last changed, so a sync from another phone keeps the newer copy.
    public var updated: Date?

    public init(id: String = UUID().uuidString, kidID: String, kind: LogKind, start: Date, end: Date? = nil,
                amountOz: Double? = nil, milk: MilkType? = nil, side: Side? = nil, diaper: DiaperKind? = nil,
                potty: PottyKind? = nil, bites: [FoodBite] = [], medicine: String = "", dose: String = "",
                temperatureF: Double? = nil, weightLb: Double? = nil, heightIn: Double? = nil, headIn: Double? = nil,
                note: String = "", photo: String = "", symptoms: [String] = [], minutes: Int? = nil, updated: Date? = nil) {
        self.id = id
        self.kidID = kidID
        self.kind = kind
        self.start = start
        self.end = end
        self.amountOz = amountOz
        self.milk = milk
        self.side = side
        self.diaper = diaper
        self.potty = potty
        self.bites = bites
        self.medicine = medicine
        self.dose = dose
        self.temperatureF = temperatureF
        self.weightLb = weightLb
        self.heightIn = heightIn
        self.headIn = headIn
        self.note = note
        self.photo = photo
        self.symptoms = symptoms
        self.minutes = minutes
        self.updated = updated
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kidID = try c.decodeIfPresent(String.self, forKey: .kidID) ?? ""
        let rawKind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kind = LogKind(rawValue: rawKind) ?? .note
        start = try c.decodeIfPresent(Date.self, forKey: .start) ?? Date(timeIntervalSince1970: 0)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        amountOz = try c.decodeIfPresent(Double.self, forKey: .amountOz)
        milk = (try? c.decodeIfPresent(MilkType.self, forKey: .milk)) ?? nil
        side = (try? c.decodeIfPresent(Side.self, forKey: .side)) ?? nil
        diaper = (try? c.decodeIfPresent(DiaperKind.self, forKey: .diaper)) ?? nil
        potty = (try? c.decodeIfPresent(PottyKind.self, forKey: .potty)) ?? nil
        bites = try c.decodeIfPresent([FoodBite].self, forKey: .bites) ?? []
        medicine = try c.decodeIfPresent(String.self, forKey: .medicine) ?? ""
        dose = try c.decodeIfPresent(String.self, forKey: .dose) ?? ""
        temperatureF = try c.decodeIfPresent(Double.self, forKey: .temperatureF)
        weightLb = try c.decodeIfPresent(Double.self, forKey: .weightLb)
        heightIn = try c.decodeIfPresent(Double.self, forKey: .heightIn)
        headIn = try c.decodeIfPresent(Double.self, forKey: .headIn)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        photo = try c.decodeIfPresent(String.self, forKey: .photo) ?? ""
        symptoms = try c.decodeIfPresent([String].self, forKey: .symptoms) ?? []
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes)
        updated = try c.decodeIfPresent(Date.self, forKey: .updated)
    }

    public var isRunning: Bool {
        kind.isTimed && end == nil
    }

    /// How long a timed entry lasted (or has lasted so far).
    public func duration(now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }

    /// One line for the timeline: "4 oz formula", "Wet + dirty", "Banana, egg".
    public func detail(now: Date, units: Units = .us) -> String {
        var parts: [String] = []
        switch kind {
        case .bottle, .pump:
            if let amountOz { parts.append(units.volume(amountOz)) }
            if let milk, kind == .bottle { parts.append(milk.title.lowercased()) }
        case .nursing:
            if let side { parts.append(side.title) }
            parts.append(isRunning ? "going for \(Dates.duration(duration(now: now)))" : Dates.duration(duration(now: now)))
        case .diaper:
            if let diaper { parts.append(diaper.title) }
        case .sleep:
            parts.append(isRunning ? "asleep for \(Dates.duration(duration(now: now)))" : Dates.duration(duration(now: now)))
        case .solids:
            let names = bites.map { FoodGuide.food($0.foodID)?.name ?? $0.foodID }
            if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
            if bites.contains(where: { $0.reaction }) { parts.append("⚠️ reaction") }
        case .potty:
            if let potty { parts.append(potty.title) }
        case .meds:
            if !medicine.isEmpty { parts.append(medicine) }
            if !dose.isEmpty { parts.append(dose) }
        case .temperature:
            if let temperatureF { parts.append(units.temperature(temperatureF)) }
        case .growth:
            if let weightLb { parts.append(units.weight(weightLb)) }
            if let heightIn { parts.append(units.length(heightIn)) }
            if let headIn { parts.append("head " + units.length(headIn)) }
        case .symptom:
            if !symptoms.isEmpty { parts.append(symptoms.joined(separator: ", ")) }
            if let temperatureF { parts.append(units.temperature(temperatureF)) }
        case .screen, .outside:
            if let minutes { parts.append(Dates.duration(Double(minutes) * 60)) }
        case .tooth, .brush, .first, .quote:
            break
        case .bath:
            break
        case .note:
            break
        }
        let line = parts.joined(separator: " · ")
        if note.isEmpty { return line }
        return line.isEmpty ? note : line + " — " + note
    }
}

public enum Measure {
    public static func oz(_ value: Double) -> String {
        trimmed(value) + " oz"
    }

    public static func inches(_ value: Double) -> String {
        trimmed(value) + " in"
    }

    /// "17 lb 4 oz" from pounds.
    public static func pounds(_ value: Double) -> String {
        let whole = Int(value)
        let ounces = Int(((value - Double(whole)) * 16).rounded())
        if ounces == 16 { return "\(whole + 1) lb" }
        return ounces == 0 ? "\(whole) lb" : "\(whole) lb \(ounces) oz"
    }

    public static func trimmed(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}

/// Everything the app saves, in one file.
public struct FamilyState: Codable {
    public var kids: [Kid]
    public var logs: [LogEntry]
    public var routines: [RoutineItem]
    public var events: [OneOffEvent]
    public var packItems: [PackItem]
    /// "day|itemID" for each pack item checked off on that day.
    public var packed: [String]
    public var activitiesDone: [ActivityDone]
    public var favoriteActivities: [String]
    /// kidID → milestoneID → status.
    public var milestones: [String: [String: MilestoneStatus]]
    /// True once the birthdays have been set on first launch.
    public var onboarded: Bool
    public var settings: FamilySettings
    /// Bedtime and morning picture charts.
    public var charts: [RoutineChart]
    /// "day|chartID|step" for each chart step done that day.
    public var chartDone: [String]
    public var contacts: [Contact]
    public var shopping: [ShoppingItem]
    /// kidID → vaccine dose ID → the day it was given (`yyyy-MM-dd`).
    public var vaccines: [String: [String: String]]
    /// kidID → the seed for that kid's weekly meal plan ("Shuffle" adds one).
    public var mealSeeds: [String: Int]
    /// IDs of things deleted on this phone, so a sync doesn't bring them back.
    public var deleted: [String]

    public init(kids: [Kid] = [], logs: [LogEntry] = [], routines: [RoutineItem] = [], events: [OneOffEvent] = [],
                packItems: [PackItem] = [], packed: [String] = [], activitiesDone: [ActivityDone] = [],
                favoriteActivities: [String] = [], milestones: [String: [String: MilestoneStatus]] = [:],
                onboarded: Bool = false, settings: FamilySettings = FamilySettings(), charts: [RoutineChart] = [],
                chartDone: [String] = [], contacts: [Contact] = [], shopping: [ShoppingItem] = [],
                vaccines: [String: [String: String]] = [:], mealSeeds: [String: Int] = [:], deleted: [String] = []) {
        self.kids = kids
        self.logs = logs
        self.routines = routines
        self.events = events
        self.packItems = packItems
        self.packed = packed
        self.activitiesDone = activitiesDone
        self.favoriteActivities = favoriteActivities
        self.milestones = milestones
        self.onboarded = onboarded
        self.settings = settings
        self.charts = charts
        self.chartDone = chartDone
        self.contacts = contacts
        self.shopping = shopping
        self.vaccines = vaccines
        self.mealSeeds = mealSeeds
        self.deleted = deleted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kids = try c.decodeIfPresent([Kid].self, forKey: .kids) ?? []
        logs = try c.decodeIfPresent([LogEntry].self, forKey: .logs) ?? []
        routines = try c.decodeIfPresent([RoutineItem].self, forKey: .routines) ?? []
        events = try c.decodeIfPresent([OneOffEvent].self, forKey: .events) ?? []
        packItems = try c.decodeIfPresent([PackItem].self, forKey: .packItems) ?? []
        packed = try c.decodeIfPresent([String].self, forKey: .packed) ?? []
        activitiesDone = try c.decodeIfPresent([ActivityDone].self, forKey: .activitiesDone) ?? []
        favoriteActivities = try c.decodeIfPresent([String].self, forKey: .favoriteActivities) ?? []
        milestones = (try? c.decodeIfPresent([String: [String: MilestoneStatus]].self, forKey: .milestones)) ?? [:]
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        settings = (try? c.decodeIfPresent(FamilySettings.self, forKey: .settings)) ?? FamilySettings()
        charts = try c.decodeIfPresent([RoutineChart].self, forKey: .charts) ?? []
        chartDone = try c.decodeIfPresent([String].self, forKey: .chartDone) ?? []
        contacts = try c.decodeIfPresent([Contact].self, forKey: .contacts) ?? []
        shopping = try c.decodeIfPresent([ShoppingItem].self, forKey: .shopping) ?? []
        vaccines = try c.decodeIfPresent([String: [String: String]].self, forKey: .vaccines) ?? [:]
        mealSeeds = try c.decodeIfPresent([String: Int].self, forKey: .mealSeeds) ?? [:]
        deleted = try c.decodeIfPresent([String].self, forKey: .deleted) ?? []
    }

    /// The first launch: Griffin and Blake, with birthdays to fill in, and
    /// starter bedtime and morning charts.
    public static func starter() -> FamilyState {
        FamilyState(kids: [
            Kid(id: "griffin", name: "Griffin", birthday: "", color: 0, emoji: "🦁"),
            Kid(id: "blake", name: "Blake", birthday: "", color: 1, emoji: "🐻"),
        ], charts: RoutineChart.starters)
    }

    public func kid(_ id: String) -> Kid? {
        kids.first { $0.id == id }
    }

    public func logs(for kidID: String) -> [LogEntry] {
        logs.filter { $0.kidID == kidID }
    }

    public var units: Units {
        settings.metric ? .metric : .us
    }
}
