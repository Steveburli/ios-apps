import Foundation

/// One vaccine dose on the routine childhood schedule.
public struct VaccineDose: Identifiable, Hashable {
    public var id: String
    public var vaccine: String
    public var short: String
    public var dose: String
    /// The usual window, in months of age.
    public var fromMonths: Int
    public var toMonths: Int
    public var note: String
}

/// A well-child checkup.
public struct Checkup: Identifiable, Hashable {
    public var id: String { "checkup-\(months)" }
    /// Age in months; 0 is the newborn visit (3–5 days).
    public var months: Int
    public var title: String
}

/// The routine childhood schedule (birth to 6 years) and checkups. Based on
/// the CDC/AAP schedules as of 2025. Schedules change, and some doses depend on
/// the brand or the child's health, so the app says to confirm with the
/// pediatrician.
public enum HealthSchedule {
    public static let doses: [VaccineDose] = [
        VaccineDose(id: "hepb1", vaccine: "Hepatitis B", short: "HepB", dose: "1st", fromMonths: 0, toMonths: 0, note: "At birth"),
        VaccineDose(id: "hepb2", vaccine: "Hepatitis B", short: "HepB", dose: "2nd", fromMonths: 1, toMonths: 2, note: ""),
        VaccineDose(id: "hepb3", vaccine: "Hepatitis B", short: "HepB", dose: "3rd", fromMonths: 6, toMonths: 18, note: ""),
        VaccineDose(id: "rsv", vaccine: "RSV antibody", short: "RSV", dose: "1 dose", fromMonths: 0, toMonths: 8,
                    note: "In RSV season if mom didn't get the RSV vaccine in pregnancy"),
        VaccineDose(id: "rv1", vaccine: "Rotavirus", short: "RV", dose: "1st", fromMonths: 2, toMonths: 2, note: "By mouth"),
        VaccineDose(id: "rv2", vaccine: "Rotavirus", short: "RV", dose: "2nd", fromMonths: 4, toMonths: 4, note: ""),
        VaccineDose(id: "rv3", vaccine: "Rotavirus", short: "RV", dose: "3rd", fromMonths: 6, toMonths: 6, note: "Depends on the brand"),
        VaccineDose(id: "dtap1", vaccine: "Diphtheria, tetanus, whooping cough", short: "DTaP", dose: "1st", fromMonths: 2, toMonths: 2, note: ""),
        VaccineDose(id: "dtap2", vaccine: "Diphtheria, tetanus, whooping cough", short: "DTaP", dose: "2nd", fromMonths: 4, toMonths: 4, note: ""),
        VaccineDose(id: "dtap3", vaccine: "Diphtheria, tetanus, whooping cough", short: "DTaP", dose: "3rd", fromMonths: 6, toMonths: 6, note: ""),
        VaccineDose(id: "dtap4", vaccine: "Diphtheria, tetanus, whooping cough", short: "DTaP", dose: "4th", fromMonths: 15, toMonths: 18, note: ""),
        VaccineDose(id: "dtap5", vaccine: "Diphtheria, tetanus, whooping cough", short: "DTaP", dose: "5th", fromMonths: 48, toMonths: 72, note: ""),
        VaccineDose(id: "hib1", vaccine: "Haemophilus influenzae type b", short: "Hib", dose: "1st", fromMonths: 2, toMonths: 2, note: ""),
        VaccineDose(id: "hib2", vaccine: "Haemophilus influenzae type b", short: "Hib", dose: "2nd", fromMonths: 4, toMonths: 4, note: ""),
        VaccineDose(id: "hib3", vaccine: "Haemophilus influenzae type b", short: "Hib", dose: "3rd", fromMonths: 6, toMonths: 6, note: "Depends on the brand"),
        VaccineDose(id: "hib4", vaccine: "Haemophilus influenzae type b", short: "Hib", dose: "Booster", fromMonths: 12, toMonths: 15, note: ""),
        VaccineDose(id: "pcv1", vaccine: "Pneumococcal", short: "PCV", dose: "1st", fromMonths: 2, toMonths: 2, note: ""),
        VaccineDose(id: "pcv2", vaccine: "Pneumococcal", short: "PCV", dose: "2nd", fromMonths: 4, toMonths: 4, note: ""),
        VaccineDose(id: "pcv3", vaccine: "Pneumococcal", short: "PCV", dose: "3rd", fromMonths: 6, toMonths: 6, note: ""),
        VaccineDose(id: "pcv4", vaccine: "Pneumococcal", short: "PCV", dose: "4th", fromMonths: 12, toMonths: 15, note: ""),
        VaccineDose(id: "ipv1", vaccine: "Polio", short: "IPV", dose: "1st", fromMonths: 2, toMonths: 2, note: ""),
        VaccineDose(id: "ipv2", vaccine: "Polio", short: "IPV", dose: "2nd", fromMonths: 4, toMonths: 4, note: ""),
        VaccineDose(id: "ipv3", vaccine: "Polio", short: "IPV", dose: "3rd", fromMonths: 6, toMonths: 18, note: ""),
        VaccineDose(id: "ipv4", vaccine: "Polio", short: "IPV", dose: "4th", fromMonths: 48, toMonths: 72, note: ""),
        VaccineDose(id: "flu", vaccine: "Flu", short: "Flu", dose: "Every fall", fromMonths: 6, toMonths: 72,
                    note: "Two doses 4 weeks apart the first season"),
        VaccineDose(id: "mmr1", vaccine: "Measles, mumps, rubella", short: "MMR", dose: "1st", fromMonths: 12, toMonths: 15, note: ""),
        VaccineDose(id: "mmr2", vaccine: "Measles, mumps, rubella", short: "MMR", dose: "2nd", fromMonths: 48, toMonths: 72, note: ""),
        VaccineDose(id: "var1", vaccine: "Chickenpox", short: "VAR", dose: "1st", fromMonths: 12, toMonths: 15, note: ""),
        VaccineDose(id: "var2", vaccine: "Chickenpox", short: "VAR", dose: "2nd", fromMonths: 48, toMonths: 72, note: ""),
        VaccineDose(id: "hepa1", vaccine: "Hepatitis A", short: "HepA", dose: "1st", fromMonths: 12, toMonths: 23, note: ""),
        VaccineDose(id: "hepa2", vaccine: "Hepatitis A", short: "HepA", dose: "2nd", fromMonths: 18, toMonths: 41, note: "6 months after the first"),
    ]

    public static let checkups: [Checkup] = [0, 1, 2, 4, 6, 9, 12, 15, 18, 24, 30, 36, 48, 60, 72].map { months in
        Checkup(months: months, title: months == 0 ? "Newborn (3–5 days)" : (months < 24 ? "\(months)-month" : (months % 12 == 0 ? "\(months / 12)-year" : "\(months / 12)½-year")))
    }

    public enum DoseState: Equatable {
        case given(String)
        case due
        case overdue
        case upcoming
    }

    /// Where a dose stands for a kid this age.
    public static func state(_ dose: VaccineDose, ageMonths: Int, given: [String: String]) -> DoseState {
        if let day = given[dose.id] { return .given(day) }
        if ageMonths > dose.toMonths { return .overdue }
        if ageMonths >= dose.fromMonths { return .due }
        return .upcoming
    }

    /// Doses due now or overdue, for the Health card.
    public static func dueNow(ageMonths: Int, given: [String: String]) -> [VaccineDose] {
        doses.filter { dose in
            let state = HealthSchedule.state(dose, ageMonths: ageMonths, given: given)
            return state == .due || state == .overdue
        }
    }

    /// The next checkup at or after this age, and the day it's due.
    public static func nextCheckup(birthday: String, today: String, calendar: Calendar = Dates.calendar) -> (Checkup, String)? {
        guard let born = Dates.date(birthday, calendar: calendar) else { return nil }
        for checkup in checkups {
            let due = calendar.date(byAdding: checkup.months == 0 ? .day : .month, value: checkup.months == 0 ? 4 : checkup.months, to: born) ?? born
            let key = Dates.key(due, calendar: calendar)
            // Still "next" for two weeks after its date.
            if Dates.addDays(key, 14, calendar: calendar) >= today { return (checkup, key) }
        }
        return nil
    }
}

/// Fever reducers and how often they can be given. The app doesn't work out
/// doses: those come from the package's weight chart or the pediatrician.
public struct MedicineRule: Identifiable, Hashable {
    public var id: String
    public var name: String
    /// Words that match a logged medicine's name.
    public var matches: [String]
    public var everyHours: Double
    public var maxPerDay: Int
    public var minMonths: Int
    public var note: String
}

public enum MedicineTimer {
    public static let rules: [MedicineRule] = [
        MedicineRule(id: "acetaminophen", name: "Acetaminophen (Tylenol)", matches: ["acetaminophen", "tylenol", "paracetamol"],
                     everyHours: 4, maxPerDay: 5, minMonths: 0,
                     note: "Every 4–6 hours, no more than 5 doses in 24 hours. Under 3 months, call the doctor before giving any."),
        MedicineRule(id: "ibuprofen", name: "Ibuprofen (Motrin, Advil)", matches: ["ibuprofen", "motrin", "advil"],
                     everyHours: 6, maxPerDay: 4, minMonths: 6,
                     note: "Every 6–8 hours, no more than 4 doses in 24 hours. Not under 6 months."),
    ]

    public static func rule(for medicine: String) -> MedicineRule? {
        let name = medicine.lowercased()
        return rules.first { rule in rule.matches.contains { name.contains($0) } }
    }

    public struct Status: Equatable {
        public var rule: MedicineRule
        public var last: Date
        /// The earliest the next dose is OK.
        public var nextOK: Date
        public var dosesToday: Int
        public var atLimit: Bool
    }

    /// For each rule with a dose in the last 24 hours: when the next is OK.
    public static func status(_ logs: [LogEntry], kidID: String, now: Date) -> [Status] {
        let since = now.addingTimeInterval(-24 * 3600)
        return rules.compactMap { rule in
            let doses = logs
                .filter { $0.kidID == kidID && $0.kind == .meds && $0.start > since && $0.start <= now && self.rule(for: $0.medicine) == rule }
                .sorted { $0.start < $1.start }
            guard let last = doses.last else { return nil }
            var next = last.start.addingTimeInterval(rule.everyHours * 3600)
            let atLimit = doses.count >= rule.maxPerDay
            if atLimit, let first = doses.first {
                // The oldest dose has to fall out of the 24 hours first.
                next = max(next, first.start.addingTimeInterval(24 * 3600))
            }
            return Status(rule: rule, last: last.start, nextOK: next, dosesToday: doses.count, atLimit: atLimit)
        }
    }
}

/// When to call the doctor, by age and symptom. General guidance.
public enum SickAdvice {
    public static let symptoms = ["Fever", "Cough", "Runny nose", "Congestion", "Vomiting", "Diarrhea", "Rash", "Ear pain",
                                  "Sore throat", "Fussy", "Not eating", "Fewer wet diapers", "Teething", "Pink eye"]

    /// Reasons to call now, given the kid's age and the latest entries.
    public static func callReasons(ageMonths: Int, temperatureF: Double?, symptoms: [String], feverHours: Double) -> [String] {
        var reasons: [String] = []
        if let temperatureF {
            if ageMonths < 3 && temperatureF >= 100.4 {
                reasons.append("Any fever of 100.4°F or higher under 3 months: call now, day or night.")
            } else if ageMonths < 6 && temperatureF >= 102 {
                reasons.append("A fever of 102°F or higher under 6 months.")
            } else if temperatureF >= 104 {
                reasons.append("A fever of 104°F or higher at any age.")
            }
        }
        if feverHours >= 72 { reasons.append("Fever lasting more than 3 days.") }
        if feverHours >= 24 && ageMonths < 24 { reasons.append("Fever over 24 hours under 2 years with no clear cause.") }
        if symptoms.contains("Fewer wet diapers") { reasons.append("Fewer wet diapers can mean dehydration.") }
        if symptoms.contains("Vomiting") && symptoms.contains("Diarrhea") { reasons.append("Vomiting with diarrhea: watch for dehydration.") }
        return reasons
    }

    public static let emergency = "Call 911 for trouble breathing, blue lips, a seizure, a stiff neck, unusual sleepiness or being hard to wake, or a rash that doesn't fade when pressed."

    /// Hours since the first fever (100.4°F or more) in the current run of
    /// fever readings, counting back until a gap of over 24 hours.
    public static func feverHours(_ logs: [LogEntry], kidID: String, now: Date) -> Double {
        let readings = logs
            .filter { $0.kidID == kidID && ($0.kind == .temperature || $0.kind == .symptom) && ($0.temperatureF ?? 0) >= 100.4 && $0.start <= now }
            .map { $0.start }
            .sorted(by: >)
        guard var first = readings.first, now.timeIntervalSince(first) < 24 * 3600 else { return 0 }
        for reading in readings.dropFirst() {
            if first.timeIntervalSince(reading) > 24 * 3600 { break }
            first = reading
        }
        return now.timeIntervalSince(first) / 3600
    }
}

/// Teeth and brushing.
public enum Teeth {
    public static func count(_ logs: [LogEntry], kidID: String) -> Int {
        logs.filter { $0.kidID == kidID && $0.kind == .tooth }.count
    }

    /// Days in a row (ending today or yesterday) with at least one brushing.
    public static func brushStreak(_ logs: [LogEntry], kidID: String, today: String, calendar: Calendar = Dates.calendar) -> Int {
        Streaks.days(Set(logs.filter { $0.kidID == kidID && $0.kind == .brush }.map { Dates.key($0.start, calendar: calendar) }),
                     today: today, calendar: calendar)
    }
}

public enum Streaks {
    /// Consecutive days in `days`, ending today or (if today isn't there yet) yesterday.
    public static func days(_ days: Set<String>, today: String, calendar: Calendar = Dates.calendar) -> Int {
        var day = days.contains(today) ? today : Dates.addDays(today, -1, calendar: calendar)
        var count = 0
        while days.contains(day) {
            count += 1
            day = Dates.addDays(day, -1, calendar: calendar)
        }
        return count
    }
}

/// Potty training: today's tally and the dry-day streak.
public enum PottyStats {
    public struct Day: Equatable {
        public var successes: Int
        public var tries: Int
        public var accidents: Int
    }

    public static func day(_ logs: [LogEntry], kidID: String, day: String, calendar: Calendar = Dates.calendar) -> Day {
        var result = Day(successes: 0, tries: 0, accidents: 0)
        for entry in logs where entry.kidID == kidID && entry.kind == .potty && Dates.key(entry.start, calendar: calendar) == day {
            switch entry.potty {
            case .some(.pee), .some(.poop), .some(.both): result.successes += 1
            case .some(.tried): result.tries += 1
            case .some(.accident): result.accidents += 1
            case .none: break
            }
        }
        return result
    }

    /// Days in a row with a success and no accident.
    public static func dryStreak(_ logs: [LogEntry], kidID: String, today: String, calendar: Calendar = Dates.calendar) -> Int {
        var good = Set<String>()
        var bad = Set<String>()
        for entry in logs where entry.kidID == kidID && entry.kind == .potty {
            let key = Dates.key(entry.start, calendar: calendar)
            if entry.potty == .accident { bad.insert(key) } else if entry.potty?.isSuccess == true { good.insert(key) }
        }
        return Streaks.days(good.subtracting(bad), today: today, calendar: calendar)
    }
}

/// Screen time and time outside for the last 7 days.
public enum TimeTotals {
    public static func week(_ logs: [LogEntry], kidID: String, kind: LogKind, today: String, calendar: Calendar = Dates.calendar) -> [(day: String, minutes: Int)] {
        (0..<7).reversed().map { offset -> (day: String, minutes: Int) in
            let day = Dates.addDays(today, -offset, calendar: calendar)
            let minutes = logs
                .filter { $0.kidID == kidID && $0.kind == kind && Dates.key($0.start, calendar: calendar) == day }
                .reduce(0) { $0 + ($1.minutes ?? 0) }
            return (day, minutes)
        }
    }
}
