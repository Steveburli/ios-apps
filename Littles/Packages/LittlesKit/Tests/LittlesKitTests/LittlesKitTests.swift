import XCTest
@testable import LittlesKit

final class LittlesKitTests: XCTestCase {
    /// UTC, so the tests don't depend on the Mac's time zone.
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Wednesday 2026-11-25 at 14:00 UTC.
    var now: Date { date("2026-11-25", 14 * 60) }

    func date(_ day: String, _ minutes: Int) -> Date {
        Dates.at(day, minutes: minutes, calendar: calendar)!
    }

    // MARK: Dates and ages

    func testDayKeys() {
        XCTAssertEqual(Dates.key(now, calendar: calendar), "2026-11-25")
        XCTAssertEqual(Dates.addDays("2026-11-25", 7, calendar: calendar), "2026-12-02")
        XCTAssertEqual(Dates.addDays("2026-03-01", -1, calendar: calendar), "2026-02-28")
        XCTAssertEqual(Dates.weekday("2026-11-25", calendar: calendar), 4)
        XCTAssertEqual(Dates.ordinal("2000-01-02", calendar: calendar), 1)
        XCTAssertNil(Dates.date("nope", calendar: calendar))
        XCTAssertEqual(Dates.clock(0), "12:00 AM")
        XCTAssertEqual(Dates.clock(12 * 60 + 5), "12:05 PM")
        XCTAssertEqual(Dates.clock(8 * 60 + 30), "8:30 AM")
        XCTAssertEqual(Dates.duration(95 * 60), "1h 35m")
        XCTAssertEqual(Dates.duration(40 * 60), "40m")
    }

    func testAges() {
        XCTAssertEqual(Age.months(birthday: "2026-03-25", on: now, calendar: calendar), 8)
        XCTAssertEqual(Age.months(birthday: "2026-03-26", on: now, calendar: calendar), 7)
        XCTAssertEqual(Age.label(birthday: "2026-11-04", on: now, calendar: calendar), "3 wk")
        XCTAssertEqual(Age.label(birthday: "2026-11-22", on: now, calendar: calendar), "3 d")
        XCTAssertEqual(Age.label(birthday: "2026-03-25", on: now, calendar: calendar), "8 mo")
        XCTAssertEqual(Age.label(birthday: "2023-07-10", on: now, calendar: calendar), "3 yr 4 mo")
        XCTAssertEqual(Age.label(birthday: "", on: now, calendar: calendar), "")
        XCTAssertEqual(Age.short(months: 30), "2½ yr")
        XCTAssertEqual(Age.short(months: 48), "4 yr")
    }

    // MARK: Logs and summaries

    func testDaySummaryCountsOnlyTodayAndSplitsSleepAtMidnight() {
        let logs = [
            LogEntry(kidID: "a", kind: .bottle, start: date("2026-11-25", 6 * 60), amountOz: 5),
            LogEntry(kidID: "a", kind: .bottle, start: date("2026-11-25", 9 * 60), amountOz: 6.5),
            LogEntry(kidID: "a", kind: .bottle, start: date("2026-11-24", 22 * 60), amountOz: 4),
            LogEntry(kidID: "b", kind: .bottle, start: date("2026-11-25", 9 * 60), amountOz: 8),
            LogEntry(kidID: "a", kind: .diaper, start: date("2026-11-25", 7 * 60), diaper: .mixed),
            LogEntry(kidID: "a", kind: .diaper, start: date("2026-11-25", 8 * 60), diaper: .wet),
            // Night sleep 20:00 to 06:00: 6 hours fall today.
            LogEntry(kidID: "a", kind: .sleep, start: date("2026-11-24", 20 * 60), end: date("2026-11-25", 6 * 60)),
            // A nap still running since 13:30: 30 minutes so far.
            LogEntry(kidID: "a", kind: .sleep, start: date("2026-11-25", 13 * 60 + 30)),
            LogEntry(kidID: "a", kind: .solids, start: date("2026-11-25", 11 * 60),
                     bites: [FoodBite(foodID: "egg"), FoodBite(foodID: "banana")]),
        ]
        let summary = Summary.day(logs, kidID: "a", on: now, now: now, calendar: calendar)
        XCTAssertEqual(summary.bottles, 2)
        XCTAssertEqual(summary.bottleOz, 11.5)
        XCTAssertEqual(summary.diapers, 2)
        XCTAssertEqual(summary.wet, 2)
        XCTAssertEqual(summary.dirty, 1)
        XCTAssertEqual(summary.sleepMinutes, 6 * 60 + 30)
        XCTAssertEqual(summary.naps, 1)
        XCTAssertEqual(summary.meals, 1)
        XCTAssertEqual(summary.foods, 2)
        XCTAssertEqual(Summary.running(logs, kidID: "a").count, 1)
        XCTAssertEqual(Summary.timeline(logs, kidID: "a", on: now, calendar: calendar).count, 7)
    }

    func testFeedGapIsTheMedianAndSkipsOvernight() {
        let starts = [date("2026-11-24", 20 * 60), date("2026-11-25", 6 * 60), date("2026-11-25", 9 * 60),
                      date("2026-11-25", 12 * 60), date("2026-11-25", 13 * 60 + 30)]
        let logs = starts.map { LogEntry(kidID: "a", kind: .bottle, start: $0) }
        // Gaps: 10h (skipped), 3h, 3h, 1.5h → median 3h.
        XCTAssertEqual(Summary.feedGap(logs, kidID: "a", now: now), 3 * 3600)
        XCTAssertEqual(Summary.nextFeed(logs, kidID: "a", now: now), date("2026-11-25", 16 * 60 + 30))
        XCTAssertNil(Summary.feedGap(Array(logs.prefix(2)), kidID: "a", now: now))
    }

    func testNextSideAlternates() {
        XCTAssertEqual(Summary.nextSide([], kidID: "a"), .left)
        let logs = [LogEntry(kidID: "a", kind: .nursing, start: date("2026-11-25", 9 * 60), end: date("2026-11-25", 9 * 60 + 10), side: .left)]
        XCTAssertEqual(Summary.nextSide(logs, kidID: "a"), .right)
    }

    func testQuickKindsChangeWithAge() {
        XCTAssertEqual(Summary.quickKinds(ageMonths: 2).first, .bottle)
        XCTAssertEqual(Summary.quickKinds(ageMonths: 40).prefix(2), [.solids, .potty])
    }

    func testDetailLines() {
        let bottle = LogEntry(kidID: "a", kind: .bottle, start: now, amountOz: 4, milk: .formula)
        XCTAssertEqual(bottle.detail(now: now), "4 oz · formula")
        let growth = LogEntry(kidID: "a", kind: .growth, start: now, weightLb: 17.25, heightIn: 27.5)
        XCTAssertEqual(growth.detail(now: now), "17 lb 4 oz · 27.5 in")
        let meal = LogEntry(kidID: "a", kind: .solids, start: now, bites: [FoodBite(foodID: "egg", reaction: true)], note: "hives on chin")
        XCTAssertEqual(meal.detail(now: now), "Egg · ⚠️ reaction — hives on chin")
    }

    // MARK: Food

    func testFoodGuideIDsAreUniqueAndAllergensHaveFoods() {
        XCTAssertEqual(Set(FoodGuide.all.map { $0.id }).count, FoodGuide.all.count)
        for allergen in Allergen.allCases {
            XCTAssertFalse(FoodGuide.foods(with: allergen).isEmpty, "\(allergen) has no food")
        }
        XCTAssertEqual(FoodGuide.food("grape")?.choke, .high)
        XCTAssertEqual(FoodGuide.food("milk")?.minMonths, 12)
        XCTAssertEqual(FoodGuide.food("egg")?.howToServe(ageMonths: 7), FoodGuide.food("egg")?.early)
        XCTAssertEqual(FoodGuide.food("egg")?.howToServe(ageMonths: 10), FoodGuide.food("egg")?.middle)
        XCTAssertEqual(FoodGuide.food("egg")?.howToServe(ageMonths: 20), FoodGuide.food("egg")?.toddler)
    }

    func testAllergenStates() {
        func meal(_ day: String, _ foodID: String, reaction: Bool = false) -> LogEntry {
            LogEntry(kidID: "a", kind: .solids, start: date(day, 12 * 60), bites: [FoodBite(foodID: foodID, reaction: reaction)])
        }
        let logs = [
            meal("2026-11-01", "egg"), meal("2026-11-05", "egg"), meal("2026-11-10", "egg"),       // due: last 15 days ago
            meal("2026-11-20", "peanut"), meal("2026-11-22", "peanut"), meal("2026-11-24", "peanut"), // in rotation
            meal("2026-11-24", "yogurt"),                                                          // introducing
            meal("2026-11-23", "salmon", reaction: true),                                          // reaction
        ]
        let states = Dictionary(uniqueKeysWithValues: FoodProgress.allergens(logs, kidID: "a", now: now).map { ($0.allergen, $0.state) })
        XCTAssertEqual(states[.egg], .due)
        XCTAssertEqual(states[.peanut], .inRotation)
        XCTAssertEqual(states[.milk], .introducing)
        XCTAssertEqual(states[.fish], .reaction)
        XCTAssertEqual(states[.sesame], .notStarted)
        XCTAssertEqual(FoodProgress.triedCount(logs, kidID: "a"), 4)
    }

    func testSuggestions() {
        let young = Kid(id: "a", name: "A", birthday: "2026-08-01", color: 0)
        XCTAssertTrue(FoodProgress.suggestions(for: young, logs: [], now: now, calendar: calendar).isEmpty)

        let baby = Kid(id: "a", name: "A", birthday: "2026-04-01", color: 0)
        let fresh = FoodProgress.suggestions(for: baby, logs: [], now: now, calendar: calendar)
        // With nothing tried: egg first, then two new non-allergen foods.
        XCTAssertEqual(fresh.first?.reason, .allergen(.egg))
        XCTAssertEqual(fresh.filter { $0.reason == .new }.count, 2)
        XCTAssertTrue(fresh.filter { $0.reason == .new }.allSatisfy { $0.food.allergen == nil })
        XCTAssertTrue(fresh.allSatisfy { $0.food.minMonths <= 7 })

        let logs = [
            LogEntry(kidID: "a", kind: .solids, start: date("2026-11-20", 12 * 60), bites: [FoodBite(foodID: "broccoli", liking: .refused)]),
            LogEntry(kidID: "a", kind: .solids, start: date("2026-11-21", 12 * 60), bites: [FoodBite(foodID: "mango", liking: .loved)]),
        ]
        let later = FoodProgress.suggestions(for: baby, logs: logs, now: now, calendar: calendar)
        XCTAssertTrue(later.contains { $0.food.id == "broccoli" && $0.reason == .tryAgain(tries: 1) })
        XCTAssertTrue(later.contains { $0.food.id == "mango" && $0.reason == .favorite })
        XCTAssertEqual(Set(later.map { $0.food.id }).count, later.count, "No food twice")

        // The same day gives the same list.
        XCTAssertEqual(later, FoodProgress.suggestions(for: baby, logs: logs, now: now.addingTimeInterval(3600), calendar: calendar))
    }

    // MARK: Activities

    func testActivitiesForBothKidsFitBothAges() {
        let both = ActivityPicker.matches(ActivityFilter(agesMonths: [8, 40]))
        XCTAssertFalse(both.isEmpty)
        XCTAssertTrue(both.allSatisfy { $0.fits(ageMonths: 8) && $0.fits(ageMonths: 40) })
        let quickInside = ActivityPicker.matches(ActivityFilter(agesMonths: [40], maxMinutes: 10, place: .inside))
        XCTAssertTrue(quickInside.allSatisfy { $0.minutes <= 10 && $0.place != .outside })
        XCTAssertEqual(Set(ActivityLibrary.all.map { $0.id }).count, ActivityLibrary.all.count)
    }

    func testRankingPutsFavoritesFirstAndRecentLast() {
        let filter = ActivityFilter(agesMonths: [40])
        let done = [ActivityDone(activityID: "letter-hunt", day: "2026-11-24", kidIDs: ["b"])]
        let ranked = ActivityPicker.ranked(filter, done: done, favorites: ["fort"], today: "2026-11-25", calendar: calendar)
        XCTAssertEqual(ranked.first?.id, "fort")
        XCTAssertEqual(ranked.last?.id, "letter-hunt")
        XCTAssertEqual(ranked.count, ActivityPicker.matches(filter).count)
    }

    // MARK: Schedule

    func schoolState() -> FamilyState {
        FamilyState(
            kids: [Kid(id: "baby", name: "Baby", birthday: "2026-03-01", color: 0), Kid(id: "big", name: "Big", birthday: "2023-06-01", color: 1)],
            routines: [
                RoutineItem(id: "school", title: "Preschool", kidIDs: ["big"], weekdays: [2, 4, 6], start: 510, end: 720, kind: .school),
                RoutineItem(id: "pickup", title: "Pickup", kidIDs: ["big"], weekdays: [2, 4, 6], start: 720, kind: .pickup),
                RoutineItem(id: "nap", title: "Nap", kidIDs: ["baby"], weekdays: [1, 2, 3, 4, 5, 6, 7], start: 780, end: 870, kind: .nap),
                RoutineItem(id: "old", title: "Last year", kidIDs: ["big"], weekdays: [4], start: 600, kind: .lesson, until: "2026-06-01"),
            ],
            events: [
                OneOffEvent(id: "off", title: "No school", day: "2026-11-27", kind: .noSchool),
                OneOffEvent(id: "pj", title: "Pajama day", kidIDs: ["big"], day: "2026-11-25", kind: .special, bring: "Pajamas"),
            ],
            packItems: [
                PackItem(id: "water", title: "Water bottle", kidID: "big"),
                PackItem(id: "book", title: "Library book", kidID: "big", weekdays: [4]),
                PackItem(id: "mon", title: "Spare clothes", kidID: "big", weekdays: [2]),
            ],
            packed: ["2026-11-25|water"])
    }

    func testAgendaOrdersAndCancels() {
        let state = schoolState()
        // Wednesday: school, pickup, nap, plus the all-day pajama day first. "Last year" has ended.
        let wednesday = Agenda.entries(on: "2026-11-25", state: state, calendar: calendar)
        XCTAssertEqual(wednesday.map { $0.id }, ["pj", "school", "pickup", "nap"])
        XCTAssertEqual(wednesday.first?.note, "Bring: Pajamas")
        // Friday has no school: the school items are struck through, the nap isn't.
        let friday = Agenda.entries(on: "2026-11-27", state: state, calendar: calendar)
        XCTAssertEqual(friday.filter { $0.cancelled }.map { $0.id }, ["school", "pickup"])
        XCTAssertTrue(Agenda.hasSchool("big", on: "2026-11-25", state: state, calendar: calendar))
        XCTAssertFalse(Agenda.hasSchool("big", on: "2026-11-27", state: state, calendar: calendar))
        // Only the baby's.
        XCTAssertEqual(Agenda.entries(on: "2026-11-25", state: state, kidID: "baby", calendar: calendar).map { $0.id }, ["nap"])
    }

    func testPackList() {
        let state = schoolState()
        let wednesday = Agenda.packList(on: "2026-11-25", state: state, calendar: calendar)
        XCTAssertEqual(wednesday.map { $0.title }, ["Water bottle", "Library book", "Pajamas"])
        XCTAssertEqual(wednesday.first?.packed, true)
        XCTAssertTrue(Agenda.packList(on: "2026-11-27", state: state, calendar: calendar).isEmpty)
        XCTAssertEqual(Agenda.packList(on: "2026-11-30", state: state, calendar: calendar).map { $0.title }, ["Water bottle", "Spare clothes"])
        XCTAssertEqual(Agenda.stalePackKeys(["2026-11-24|a", "2026-11-25|b"], today: "2026-11-25"), ["2026-11-24|a"])
    }

    func testNextAgendaEntry() {
        let state = schoolState()
        // 14:00 Wednesday: everything today has started, so the next is Thursday's nap.
        let next = Agenda.next(after: now, state: state, calendar: calendar)
        XCTAssertEqual(next?.day, "2026-11-26")
        XCTAssertEqual(next?.entry.id, "nap")
    }

    func testRoutineDaysLabel() {
        XCTAssertEqual(RoutineItem(title: "", weekdays: [2, 3, 4, 5, 6], start: 0, kind: .school).daysLabel, "Weekdays")
        XCTAssertEqual(RoutineItem(title: "", weekdays: [6, 2, 4], start: 0, kind: .school).daysLabel, "Mon, Wed, Fri")
    }

    // MARK: Milestones and tips

    func testMilestones() {
        XCTAssertEqual(Set(Milestones.all.map { $0.id }).count, Milestones.all.count)
        for age in Milestones.ages { XCTAssertFalse(Milestones.list(for: age).isEmpty, "No milestones at \(age)") }
        XCTAssertEqual(Milestones.current(ageMonths: 0), 2)
        XCTAssertEqual(Milestones.current(ageMonths: 8), 6)
        XCTAssertEqual(Milestones.upcoming(ageMonths: 8), 9)
        XCTAssertEqual(Milestones.current(ageMonths: 40), 36)
        XCTAssertNil(Milestones.upcoming(ageMonths: 70))
        let first = Milestones.list(for: 4)[0].id
        XCTAssertEqual(Milestones.progress(months: 4, statuses: [first: .yes]).done, 1)
        XCTAssertEqual(Milestones.toMention(ageMonths: 8, statuses: [first: .notYet]).map { $0.id }, [first])
        XCTAssertEqual(Milestones.ageTitle(30), "2½ years")
    }

    func testTips() {
        XCTAssertEqual(Set(Tips.all.map { $0.id }).count, Tips.all.count)
        XCTAssertEqual(Tips.ofTheDay("2026-11-25", calendar: calendar), Tips.ofTheDay("2026-11-25", calendar: calendar))
        XCTAssertNotEqual(Tips.ofTheDay("2026-11-25", calendar: calendar), Tips.ofTheDay("2026-11-26", calendar: calendar))
        for situation in TipSituation.allCases { XCTAssertFalse(Tips.tips(for: situation).isEmpty, "\(situation)") }
    }

    // MARK: Saving

    func testStateRoundTripsAndOldFilesLoad() throws {
        let state = Sample.family(now: now, calendar: calendar)
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(FamilyState.self, from: data)
        XCTAssertEqual(back.kids, state.kids)
        XCTAssertEqual(back.logs, state.logs)
        XCTAssertEqual(back.routines, state.routines)
        XCTAssertEqual(back.milestones, state.milestones)

        // A file from an older build, missing most fields and with a kind this build doesn't know.
        let old = #"{"kids":[{"id":"g","name":"Griffin"}],"logs":[{"kidID":"g","kind":"teleport","start":0}]}"#
        let loaded = try JSONDecoder().decode(FamilyState.self, from: Data(old.utf8))
        XCTAssertEqual(loaded.kids.first?.birthday, "")
        XCTAssertEqual(loaded.logs.first?.kind, .note)
        XCTAssertFalse(loaded.onboarded)
        XCTAssertTrue(loaded.routines.isEmpty)
    }

    func testSampleFamilyUsesRealFoodsAndActivities() {
        let state = Sample.family(now: now, calendar: calendar)
        for entry in state.logs { for bite in entry.bites { XCTAssertNotNil(FoodGuide.food(bite.foodID), bite.foodID) } }
        for done in state.activitiesDone { XCTAssertNotNil(ActivityLibrary.activity(done.activityID)) }
        for id in state.favoriteActivities { XCTAssertNotNil(ActivityLibrary.activity(id)) }
        XCTAssertEqual(state.kid(Sample.babyID)?.ageMonths(on: now, calendar: calendar), 8)
        XCTAssertEqual(state.kid(Sample.bigID)?.ageMonths(on: now, calendar: calendar), 40)
        XCTAssertGreaterThan(FoodProgress.triedCount(state.logs, kidID: Sample.babyID), 20)
        XCTAssertEqual(FamilyState.starter().kids.map { $0.name }, ["Griffin", "Blake"])
    }
}
