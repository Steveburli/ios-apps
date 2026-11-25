import Foundation

/// Made-up data for the screenshots and the tests: a baby and a preschooler
/// with a few days of logs, a preschool schedule and some milestones.
public enum Sample {
    public static let babyID = "griffin"
    public static let bigID = "blake"

    public static func family(now: Date, calendar: Calendar = Dates.calendar) -> FamilyState {
        let today = Dates.key(now, calendar: calendar)
        func birthday(monthsAgo: Int) -> String {
            let date = calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
            return Dates.key(calendar.date(byAdding: .day, value: -9, to: date) ?? date, calendar: calendar)
        }
        func at(_ dayOffset: Int, _ minutes: Int) -> Date {
            Dates.at(Dates.addDays(today, dayOffset, calendar: calendar), minutes: minutes, calendar: calendar) ?? now
        }
        let baby = Kid(id: babyID, name: "Griffin", birthday: birthday(monthsAgo: 8), color: 0, emoji: "🦁")
        let big = Kid(id: bigID, name: "Blake", birthday: birthday(monthsAgo: 40), color: 1, emoji: "🐻")
        let nowMinutes = Dates.minutes(now, calendar: calendar)

        var logs: [LogEntry] = []
        // The baby's last three days of bottles, diapers and naps, up to now.
        let ounces: [Double] = [5, 6, 6, 5, 7]
        for day in -2...0 {
            for minute in [6 * 60 + 10, 9 * 60 + 30, 12 * 60 + 40, 15 * 60 + 45, 19 * 60] {
                let time = at(day, minute)
                guard time <= now else { continue }
                logs.append(LogEntry(kidID: babyID, kind: .bottle, start: time, amountOz: ounces[minute % 5], milk: .formula))
            }
            for (index, minute) in [6 * 60 + 5, 8 * 60 + 45, 11 * 60 + 20, 14 * 60, 16 * 60 + 30, 18 * 60 + 50].enumerated() {
                let time = at(day, minute)
                guard time <= now else { continue }
                logs.append(LogEntry(kidID: babyID, kind: .diaper, start: time, diaper: index == 2 ? .mixed : (index == 4 ? .dirty : .wet)))
            }
            for (start, length) in [(9 * 60 + 45, 75), (13 * 60 + 30, 90)] {
                let begin = at(day, start)
                guard begin <= now else { continue }
                let end = begin.addingTimeInterval(Double(length) * 60)
                logs.append(LogEntry(kidID: babyID, kind: .sleep, start: begin, end: end <= now ? end : nil))
            }
        }
        // Night sleep that ended this morning.
        logs.append(LogEntry(kidID: babyID, kind: .sleep, start: at(-1, 19 * 60 + 30), end: at(0, 6 * 60)))

        // Meals over the past few weeks so the Food tab has progress and allergens.
        let babyMeals: [(Int, [FoodBite])] = [
            (-24, [FoodBite(foodID: "avocado", liking: .loved), FoodBite(foodID: "banana")]),
            (-22, [FoodBite(foodID: "sweetpotato", liking: .loved), FoodBite(foodID: "egg")]),
            (-20, [FoodBite(foodID: "broccoli", liking: .refused), FoodBite(foodID: "oats")]),
            (-18, [FoodBite(foodID: "egg"), FoodBite(foodID: "peanut")]),
            (-16, [FoodBite(foodID: "mango", liking: .loved), FoodBite(foodID: "yogurt")]),
            (-14, [FoodBite(foodID: "peanut"), FoodBite(foodID: "salmon"), FoodBite(foodID: "zucchini", liking: .meh)]),
            (-12, [FoodBite(foodID: "toast"), FoodBite(foodID: "egg", liking: .loved), FoodBite(foodID: "strawberry")]),
            (-10, [FoodBite(foodID: "yogurt", liking: .loved), FoodBite(foodID: "blueberry"), FoodBite(foodID: "peanut")]),
            (-9, [FoodBite(foodID: "chicken"), FoodBite(foodID: "butternut"), FoodBite(foodID: "pear")]),
            (-8, [FoodBite(foodID: "tofu"), FoodBite(foodID: "rice"), FoodBite(foodID: "broccoli", liking: .refused)]),
            (-6, [FoodBite(foodID: "pasta"), FoodBite(foodID: "cheese", liking: .loved), FoodBite(foodID: "peas")]),
            (-4, [FoodBite(foodID: "egg"), FoodBite(foodID: "toast"), FoodBite(foodID: "watermelon", liking: .loved)]),
            (-3, [FoodBite(foodID: "beef"), FoodBite(foodID: "potato"), FoodBite(foodID: "greenbeans")]),
            (-2, [FoodBite(foodID: "peanut"), FoodBite(foodID: "oats"), FoodBite(foodID: "raspberry")]),
            (-1, [FoodBite(foodID: "lentils"), FoodBite(foodID: "cauliflower", liking: .meh), FoodBite(foodID: "kiwi")]),
            (0, [FoodBite(foodID: "egg", liking: .loved), FoodBite(foodID: "avocado")]),
        ]
        for (day, bites) in babyMeals {
            let time = at(day, 11 * 60 + 30)
            guard time <= now else { continue }
            logs.append(LogEntry(kidID: babyID, kind: .solids, start: time, bites: bites))
        }

        // The preschooler: meals, potty and a nap.
        logs.append(LogEntry(kidID: bigID, kind: .solids, start: at(0, 7 * 60 + 15),
                             bites: [FoodBite(foodID: "oats", liking: .liked), FoodBite(foodID: "banana", liking: .loved)]))
        logs.append(LogEntry(kidID: bigID, kind: .potty, start: at(0, 7 * 60 + 5), potty: .pee))
        if nowMinutes > 12 * 60 + 30 {
            logs.append(LogEntry(kidID: bigID, kind: .solids, start: at(0, 12 * 60 + 15),
                                 bites: [FoodBite(foodID: "pasta", liking: .loved), FoodBite(foodID: "broccoli", liking: .refused)]))
            logs.append(LogEntry(kidID: bigID, kind: .potty, start: at(0, 12 * 60 + 40), potty: .both))
        }
        logs.append(LogEntry(kidID: bigID, kind: .potty, start: at(-1, 16 * 60), potty: .accident))
        logs.append(LogEntry(kidID: bigID, kind: .meds, start: at(-1, 20 * 60), medicine: "Children's ibuprofen", dose: "5 mL",
                             note: "Low fever after school"))
        logs.append(LogEntry(kidID: bigID, kind: .temperature, start: at(-1, 19 * 60 + 50), temperatureF: 100.6))

        // Growth from checkups.
        for (monthsAgo, pounds, inches) in [(8, 7.6, 20.0), (6, 12.4, 23.5), (4, 15.1, 25.2), (2, 17.0, 26.6), (0, 18.4, 27.8)] {
            let date = calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
            logs.append(LogEntry(kidID: babyID, kind: .growth, start: date.addingTimeInterval(-3600), weightLb: pounds, heightIn: inches))
        }
        for (monthsAgo, pounds, inches) in [(12, 30.1, 36.0), (6, 32.0, 37.5), (1, 33.6, 38.6)] {
            let date = calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
            logs.append(LogEntry(kidID: bigID, kind: .growth, start: date, weightLb: pounds, heightIn: inches))
        }

        // Preschool three mornings a week, and swim on Saturdays.
        let routines = [
            RoutineItem(id: "drop", title: "Drop-off", kidIDs: [bigID], weekdays: [2, 4, 6], start: 8 * 60 + 15,
                        kind: .dropoff, place: "Little Acorns Preschool"),
            RoutineItem(id: "school", title: "Preschool", kidIDs: [bigID], weekdays: [2, 4, 6], start: 8 * 60 + 30,
                        end: 12 * 60, kind: .school, place: "Little Acorns Preschool", note: "Room 3 · Ms. Rivera"),
            RoutineItem(id: "pickup", title: "Pickup", kidIDs: [bigID], weekdays: [2, 4, 6], start: 12 * 60,
                        kind: .pickup, remind: 20),
            RoutineItem(id: "nap1", title: "Morning nap", kidIDs: [babyID], weekdays: [1, 2, 3, 4, 5, 6, 7], start: 9 * 60 + 45,
                        end: 11 * 60, kind: .nap),
            RoutineItem(id: "nap2", title: "Afternoon nap", kidIDs: [babyID, bigID], weekdays: [1, 2, 3, 4, 5, 6, 7], start: 13 * 60 + 30,
                        end: 15 * 60, kind: .nap),
            RoutineItem(id: "swim", title: "Swim class", kidIDs: [bigID], weekdays: [7], start: 9 * 60 + 30, end: 10 * 60,
                        kind: .lesson, place: "Y pool"),
        ]
        // A special day on the next school day, and a day off the week after.
        var schoolDays: [String] = []
        for offset in 1...14 {
            let day = Dates.addDays(today, offset, calendar: calendar)
            if [2, 4, 6].contains(Dates.weekday(day, calendar: calendar)) { schoolDays.append(day) }
        }
        var events: [OneOffEvent] = []
        if schoolDays.count >= 3 {
            events.append(OneOffEvent(id: "pj", title: "Pajama day", kidIDs: [bigID], day: schoolDays[0], kind: .special,
                                      bring: "Wear pajamas + a stuffed animal"))
            events.append(OneOffEvent(id: "off", title: "No school: teacher workday", kidIDs: [], day: schoolDays[2], kind: .noSchool))
        }
        events.append(OneOffEvent(id: "checkup", title: "Griffin's 9-month checkup", kidIDs: [babyID],
                                  day: Dates.addDays(today, 5, calendar: calendar), start: 10 * 60 + 20, kind: .doctor,
                                  note: "Dr. Patel", bring: "Shot record"))

        let packItems = [
            PackItem(id: "water", title: "Water bottle", kidID: bigID),
            PackItem(id: "clothes", title: "Spare clothes", kidID: bigID, weekdays: [2]),
            PackItem(id: "library", title: "Library book", kidID: bigID, weekdays: [4]),
            PackItem(id: "share", title: "Show-and-tell", kidID: bigID, weekdays: [6]),
        ]

        var milestones: [String: [String: MilestoneStatus]] = [:]
        var babyMarks: [String: MilestoneStatus] = [:]
        for item in Milestones.all where item.months <= 6 { babyMarks[item.id] = .yes }
        for (index, item) in Milestones.list(for: 9).enumerated() { babyMarks[item.id] = index < 7 ? MilestoneStatus.yes : (index == 8 ? MilestoneStatus.unsure : MilestoneStatus.notYet) }
        milestones[babyID] = babyMarks
        var bigMarks: [String: MilestoneStatus] = [:]
        for item in Milestones.all where item.months <= 30 { bigMarks[item.id] = .yes }
        for (index, item) in Milestones.list(for: 36).enumerated() { bigMarks[item.id] = index < 9 ? MilestoneStatus.yes : MilestoneStatus.notYet }
        milestones[bigID] = bigMarks

        let done = [
            ActivityDone(activityID: "bubbles-baby", day: Dates.addDays(today, -1, calendar: calendar), kidIDs: [babyID, bigID]),
            ActivityDone(activityID: "playdough", day: Dates.addDays(today, -2, calendar: calendar), kidIDs: [bigID]),
        ]

        return FamilyState(kids: [baby, big], logs: logs, routines: routines, events: events, packItems: packItems,
                           packed: [], activitiesDone: done, favoriteActivities: ["board-books", "dance-freeze"],
                           milestones: milestones, onboarded: true)
    }
}
