import Foundation

/// How amounts show. Values are always saved in US units (oz, lb, in, °F).
public struct Units: Equatable {
    public var isMetric: Bool

    public static let us = Units(isMetric: false)
    public static let metric = Units(isMetric: true)

    public static let mlPerOz = 29.5735
    public static let kgPerLb = 0.45359237
    public static let cmPerIn = 2.54

    public func volume(_ oz: Double) -> String {
        isMetric ? "\(Int((oz * Units.mlPerOz / 5).rounded() * 5)) ml" : Measure.oz(oz)
    }

    public func weight(_ lb: Double) -> String {
        isMetric ? String(format: "%.2f kg", lb * Units.kgPerLb) : Measure.pounds(lb)
    }

    public func length(_ inches: Double) -> String {
        isMetric ? String(format: "%.1f cm", inches * Units.cmPerIn) : Measure.inches(inches)
    }

    public func temperature(_ fahrenheit: Double) -> String {
        isMetric ? String(format: "%.1f°C", (fahrenheit - 32) * 5 / 9) : String(format: "%.1f°F", fahrenheit)
    }

    /// The unit labels for editors.
    public var volumeUnit: String { isMetric ? "ml" : "oz" }
    public var weightUnit: String { isMetric ? "kg" : "lb" }
    public var lengthUnit: String { isMetric ? "cm" : "in" }
    public var temperatureUnit: String { isMetric ? "°C" : "°F" }

    /// Saved value (US) to the shown number, and back.
    public func showVolume(_ oz: Double) -> Double { isMetric ? oz * Units.mlPerOz : oz }
    public func saveVolume(_ shown: Double) -> Double { isMetric ? shown / Units.mlPerOz : shown }
    public func showWeight(_ lb: Double) -> Double { isMetric ? lb * Units.kgPerLb : lb }
    public func saveWeight(_ shown: Double) -> Double { isMetric ? shown / Units.kgPerLb : shown }
    public func showLength(_ inches: Double) -> Double { isMetric ? inches * Units.cmPerIn : inches }
    public func saveLength(_ shown: Double) -> Double { isMetric ? shown / Units.cmPerIn : shown }
    public func showTemperature(_ f: Double) -> Double { isMetric ? (f - 32) * 5 / 9 : f }
    public func saveTemperature(_ shown: Double) -> Double { isMetric ? shown * 9 / 5 + 32 : shown }
}

public enum NightMode: String, Codable, CaseIterable, Identifiable {
    case off, on, auto
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .auto: return "9 PM to 6 AM"
        }
    }

    /// Whether the dim red night theme shows at this minute of the day.
    public func isActive(minute: Int) -> Bool {
        switch self {
        case .off: return false
        case .on: return true
        case .auto: return minute >= 21 * 60 || minute < 6 * 60
        }
    }
}

/// Potty training mode for one kid: reminders every so often during the day.
public struct PottyPlan: Codable, Equatable {
    public var on: Bool
    public var every: Int
    public var from: Int
    public var to: Int

    public init(on: Bool = false, every: Int = 45, from: Int = 8 * 60, to: Int = 19 * 60) {
        self.on = on
        self.every = every
        self.from = from
        self.to = to
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? false
        every = try c.decodeIfPresent(Int.self, forKey: .every) ?? 45
        from = try c.decodeIfPresent(Int.self, forKey: .from) ?? 8 * 60
        to = try c.decodeIfPresent(Int.self, forKey: .to) ?? 19 * 60
    }

    /// The reminder times of day, every `every` minutes from `from` up to `to`.
    public var times: [Int] {
        guard on, every >= 10, to > from else { return [] }
        return Array(stride(from: from + every, through: to, by: every))
    }
}

public struct FamilySettings: Codable, Equatable {
    /// ml, kg, cm and °C instead of oz, lb, in and °F.
    public var metric: Bool
    public var nightMode: NightMode
    /// Minutes to get to preschool, for the "leave in…" countdown.
    public var travelMinutes: Int
    /// The morning countdown card and its "leave in 15 minutes" reminder.
    public var countdown: Bool
    /// A notification when the next dose of a fever reducer is OK.
    public var medicineReminders: Bool
    /// kidID → potty training plan.
    public var potty: [String: PottyPlan]
    /// A reminder a week before each checkup and vaccine due date.
    public var checkupReminders: Bool

    public init(metric: Bool = false, nightMode: NightMode = .off, travelMinutes: Int = 15, countdown: Bool = true,
                medicineReminders: Bool = true, potty: [String: PottyPlan] = [:], checkupReminders: Bool = true) {
        self.metric = metric
        self.nightMode = nightMode
        self.travelMinutes = travelMinutes
        self.countdown = countdown
        self.medicineReminders = medicineReminders
        self.potty = potty
        self.checkupReminders = checkupReminders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metric = try c.decodeIfPresent(Bool.self, forKey: .metric) ?? false
        nightMode = (try? c.decodeIfPresent(NightMode.self, forKey: .nightMode)) ?? .off
        travelMinutes = try c.decodeIfPresent(Int.self, forKey: .travelMinutes) ?? 15
        countdown = try c.decodeIfPresent(Bool.self, forKey: .countdown) ?? true
        medicineReminders = try c.decodeIfPresent(Bool.self, forKey: .medicineReminders) ?? true
        potty = (try? c.decodeIfPresent([String: PottyPlan].self, forKey: .potty)) ?? [:]
        checkupReminders = try c.decodeIfPresent(Bool.self, forKey: .checkupReminders) ?? true
    }
}

/// A picture checklist a kid follows: bedtime, morning, getting out the door.
public struct RoutineChart: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var emoji: String
    /// Empty means every kid.
    public var kidIDs: [String]
    public var steps: [ChartStep]

    public init(id: String = UUID().uuidString, title: String, emoji: String, kidIDs: [String] = [], steps: [ChartStep]) {
        self.id = id
        self.title = title
        self.emoji = emoji
        self.kidIDs = kidIDs
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "✅"
        kidIDs = try c.decodeIfPresent([String].self, forKey: .kidIDs) ?? []
        steps = try c.decodeIfPresent([ChartStep].self, forKey: .steps) ?? []
    }

    public static func key(day: String, chartID: String, kidID: String, step: Int) -> String {
        "\(day)|\(chartID)|\(kidID)|\(step)"
    }

    /// How many steps are done today for a kid.
    public func done(day: String, kidID: String, keys: [String]) -> Int {
        let set = Set(keys)
        return steps.indices.filter { set.contains(RoutineChart.key(day: day, chartID: id, kidID: kidID, step: $0)) }.count
    }

    /// Days in a row (ending today or yesterday) the whole chart was finished.
    public func streak(today: String, kidID: String, keys: [String], calendar: Calendar = Dates.calendar) -> Int {
        guard !steps.isEmpty else { return 0 }
        var day = today
        if done(day: day, kidID: kidID, keys: keys) < steps.count { day = Dates.addDays(day, -1, calendar: calendar) }
        var count = 0
        while done(day: day, kidID: kidID, keys: keys) == steps.count {
            count += 1
            day = Dates.addDays(day, -1, calendar: calendar)
        }
        return count
    }

    public static let starters: [RoutineChart] = [
        RoutineChart(id: "bedtime", title: "Bedtime", emoji: "🌙", steps: [
            ChartStep(emoji: "🛁", title: "Bath"), ChartStep(emoji: "👕", title: "Pajamas"),
            ChartStep(emoji: "🪥", title: "Brush teeth"), ChartStep(emoji: "🚽", title: "Potty"),
            ChartStep(emoji: "📚", title: "Two books"), ChartStep(emoji: "🎵", title: "Song and hugs"),
            ChartStep(emoji: "😴", title: "Lights out"),
        ]),
        RoutineChart(id: "morning", title: "Morning", emoji: "☀️", steps: [
            ChartStep(emoji: "🚽", title: "Potty"), ChartStep(emoji: "👕", title: "Get dressed"),
            ChartStep(emoji: "🥣", title: "Breakfast"), ChartStep(emoji: "🪥", title: "Brush teeth"),
            ChartStep(emoji: "👟", title: "Shoes on"), ChartStep(emoji: "🎒", title: "Backpack"),
        ]),
    ]
}

public struct ChartStep: Codable, Hashable {
    public var emoji: String
    public var title: String

    public init(emoji: String, title: String) {
        self.emoji = emoji
        self.title = title
    }
}

/// A teacher, a classmate's parent, the pediatrician.
public struct Contact: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var role: String
    public var phone: String
    public var email: String
    /// Empty for everyone.
    public var kidID: String
    public var note: String

    public init(id: String = UUID().uuidString, name: String, role: String = "", phone: String = "", email: String = "",
                kidID: String = "", note: String = "") {
        self.id = id
        self.name = name
        self.role = role
        self.phone = phone
        self.email = email
        self.kidID = kidID
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        kidID = try c.decodeIfPresent(String.self, forKey: .kidID) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// One thing to buy: groceries from the meal plan or anything for school.
public struct ShoppingItem: Codable, Identifiable, Hashable {
    public var id: String
    public var title: String
    /// "Groceries", "School", "Party" or anything else.
    public var list: String
    public var done: Bool

    public init(id: String = UUID().uuidString, title: String, list: String = "Groceries", done: Bool = false) {
        self.id = id
        self.title = title
        self.list = list
        self.done = done
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        list = try c.decodeIfPresent(String.self, forKey: .list) ?? "Groceries"
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}
