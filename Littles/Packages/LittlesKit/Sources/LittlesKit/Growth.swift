import Foundation

/// Growth percentiles from the WHO Child Growth Standards (birth to 5 years),
/// the charts US pediatricians use under 2 and many use to 5.
public enum Growth {
    public enum Kind {
        case weight, height
    }

    /// The percentile (0–100) for a measurement at an age, or nil past 5
    /// years or without a known sex. Weight in pounds, height in inches.
    public static func percentile(_ measure: Kind, value: Double, ageDays: Int, sex: String) -> Double? {
        guard let z = zScore(measure, value: value, ageDays: ageDays, sex: sex) else { return nil }
        return normalCDF(z) * 100
    }

    public static func zScore(_ measure: Kind, value: Double, ageDays: Int, sex: String) -> Double? {
        let table: [WHOTables.Row]
        switch (measure, sex) {
        case (.weight, "boy"): table = WHOTables.weightBoys
        case (.weight, "girl"): table = WHOTables.weightGirls
        case (.height, "boy"): table = WHOTables.heightBoys
        case (.height, "girl"): table = WHOTables.heightGirls
        default: return nil
        }
        guard let lms = interpolate(table, day: ageDays), value > 0 else { return nil }
        let x = measure == .weight ? value * Units.kgPerLb : value * Units.cmPerIn
        if abs(lms.l) < 1e-9 { return log(x / lms.m) / lms.s }
        return (pow(x / lms.m, lms.l) - 1) / (lms.l * lms.s)
    }

    static func interpolate(_ table: [WHOTables.Row], day: Int) -> (l: Double, m: Double, s: Double)? {
        guard day >= 0, let last = table.last, day <= last.day else { return nil }
        guard let upper = table.firstIndex(where: { $0.day >= day }) else { return nil }
        let hi = table[upper]
        if hi.day == day || upper == 0 { return (hi.l, hi.m, hi.s) }
        let lo = table[upper - 1]
        let t = Double(day - lo.day) / Double(hi.day - lo.day)
        return (lo.l + (hi.l - lo.l) * t, lo.m + (hi.m - lo.m) * t, lo.s + (hi.s - lo.s) * t)
    }

    public static func normalCDF(_ z: Double) -> Double {
        0.5 * (1 + erf(z / 2.0.squareRoot()))
    }

    /// "52nd percentile", with the right ending.
    public static func label(_ percentile: Double) -> String {
        let value = max(1, min(99, Int(percentile.rounded())))
        let suffix: String
        switch value % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch value % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(value)\(suffix) percentile"
    }

    /// The age in days for a moment, from a birthday.
    public static func ageDays(birthday: String, at date: Date, calendar: Calendar = Dates.calendar) -> Int {
        Age.days(birthday: birthday, on: date, calendar: calendar)
    }
}

/// General sleep guidance by age: awake windows and naps, used to guess the
/// next nap. Ranges follow common pediatric sleep guidance; every kid differs.
public enum SleepGuide {
    public struct Window: Equatable {
        public var minMinutes: Int
        public var maxMinutes: Int
        public var naps: String
        public var totalHours: String
    }

    public static func window(ageMonths: Int) -> Window {
        switch ageMonths {
        case ..<1: return Window(minMinutes: 35, maxMinutes: 60, naps: "4–8", totalHours: "14–17")
        case 1..<3: return Window(minMinutes: 60, maxMinutes: 90, naps: "4–5", totalHours: "14–17")
        case 3..<5: return Window(minMinutes: 75, maxMinutes: 120, naps: "3–4", totalHours: "12–16")
        case 5..<7: return Window(minMinutes: 120, maxMinutes: 180, naps: "2–3", totalHours: "12–16")
        case 7..<10: return Window(minMinutes: 150, maxMinutes: 210, naps: "2", totalHours: "12–16")
        case 10..<15: return Window(minMinutes: 180, maxMinutes: 240, naps: "1–2", totalHours: "11–14")
        case 15..<24: return Window(minMinutes: 300, maxMinutes: 360, naps: "1", totalHours: "11–14")
        case 24..<36: return Window(minMinutes: 300, maxMinutes: 360, naps: "0–1", totalHours: "11–14")
        default: return Window(minMinutes: 360, maxMinutes: 720, naps: "0–1", totalHours: "10–13")
        }
    }

    /// When the next sleep window opens and closes: the last wake-up plus the
    /// awake window for the age. Nil while asleep or with no sleep logged.
    public static func nextSleep(_ logs: [LogEntry], kidID: String, ageMonths: Int, now: Date) -> (from: Date, to: Date)? {
        guard let last = Summary.last(logs, kidID: kidID, kinds: [.sleep]), let woke = last.end else { return nil }
        // An old wake-up (over 14 hours ago) is no help.
        guard now.timeIntervalSince(woke) < 14 * 3600 else { return nil }
        let window = SleepGuide.window(ageMonths: ageMonths)
        return (woke.addingTimeInterval(Double(window.minMinutes) * 60), woke.addingTimeInterval(Double(window.maxMinutes) * 60))
    }
}
