import XCTest
@testable import LittlesKit

/// Tests for the second round of features: health, food planning, imports,
/// sync, reports and the rest.
final class FeatureTests: XCTestCase {
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

    func meal(_ day: String, _ ids: [String], liking: Liking = .liked, reaction: Bool = false) -> LogEntry {
        LogEntry(kidID: "a", kind: .solids, start: date(day, 12 * 60), bites: ids.map { FoodBite(foodID: $0, liking: liking, reaction: reaction) })
    }

    // MARK: Growth and sleep

    func testPercentilesAtTheWHOMedianAreFifty() throws {
        let weightRow = WHOTables.weightBoys[24]
        let weight = try XCTUnwrap(Growth.percentile(.weight, value: weightRow.m / Units.kgPerLb, ageDays: weightRow.day, sex: "boy"))
        XCTAssertEqual(weight, 50, accuracy: 0.01)
        let heightRow = WHOTables.heightGirls[60]
        let height = try XCTUnwrap(Growth.percentile(.height, value: heightRow.m / Units.cmPerIn, ageDays: heightRow.day, sex: "girl"))
        XCTAssertEqual(height, 50, accuracy: 0.01)
        let medianWeight = 9.646 / Units.kgPerLb
        // Heavier than the median is above 50; girls use their own table.
        XCTAssertGreaterThan(Growth.percentile(.weight, value: medianWeight + 3, ageDays: 365, sex: "boy")!, 85)
        XCTAssertNotNil(Growth.percentile(.weight, value: 20, ageDays: 400, sex: "girl"))
        XCTAssertNil(Growth.percentile(.weight, value: 20, ageDays: 400, sex: ""))
        XCTAssertNil(Growth.percentile(.weight, value: 40, ageDays: 2000, sex: "boy"))
        XCTAssertEqual(Growth.label(52.3), "52nd percentile")
        XCTAssertEqual(Growth.label(11), "11th percentile")
        XCTAssertEqual(Growth.label(0.2), "1st percentile")
        XCTAssertEqual(Growth.label(23), "23rd percentile")
    }

    func testNextSleepWindow() {
        let logs = [LogEntry(kidID: "a", kind: .sleep, start: date("2026-11-25", 11 * 60), end: date("2026-11-25", 12 * 60))]
        let window = SleepGuide.nextSleep(logs, kidID: "a", ageMonths: 8, now: now)
        XCTAssertEqual(window?.from, date("2026-11-25", 14 * 60 + 30))
        XCTAssertEqual(window?.to, date("2026-11-25", 15 * 60 + 30))
        XCTAssertNil(SleepGuide.nextSleep([LogEntry(kidID: "a", kind: .sleep, start: now)], kidID: "a", ageMonths: 8, now: now))
    }

    // MARK: Settings

    func testUnits() {
        XCTAssertEqual(Units.metric.volume(4), "120 ml")
        XCTAssertEqual(Units.us.volume(4), "4 oz")
        XCTAssertEqual(Units.metric.weight(10), "4.54 kg")
        XCTAssertEqual(Units.metric.temperature(98.6), "37.0°C")
        XCTAssertEqual(Units.metric.length(10), "25.4 cm")
        XCTAssertEqual(Units.metric.saveTemperature(Units.metric.showTemperature(101)), 101, accuracy: 0.0001)
        XCTAssertEqual(Units.metric.saveVolume(Units.metric.showVolume(5)), 5, accuracy: 0.0001)
    }

    func testNightModeAndPottyTimes() {
        XCTAssertTrue(NightMode.auto.isActive(minute: 22 * 60))
        XCTAssertTrue(NightMode.auto.isActive(minute: 3 * 60))
        XCTAssertFalse(NightMode.auto.isActive(minute: 12 * 60))
        XCTAssertEqual(PottyPlan(on: true, every: 60, from: 480, to: 600).times, [540, 600])
        XCTAssertEqual(PottyPlan(on: false).times, [])
    }

    func testChartStreak() {
        let chart = RoutineChart(id: "c", title: "Bed", emoji: "🌙", steps: [ChartStep(emoji: "🛁", title: "Bath"), ChartStep(emoji: "📚", title: "Book")])
        var keys: [String] = []
        for day in ["2026-11-22", "2026-11-23", "2026-11-24"] {
            keys += [RoutineChart.key(day: day, chartID: "c", kidID: "k", step: 0), RoutineChart.key(day: day, chartID: "c", kidID: "k", step: 1)]
        }
        keys.append(RoutineChart.key(day: "2026-11-25", chartID: "c", kidID: "k", step: 0))
        XCTAssertEqual(chart.done(day: "2026-11-25", kidID: "k", keys: keys), 1)
        XCTAssertEqual(chart.streak(today: "2026-11-25", kidID: "k", keys: keys, calendar: calendar), 3)
    }

    // MARK: Health

    func testVaccinesAndCheckups() {
        let dtap1 = HealthSchedule.doses.first { $0.id == "dtap1" }!
        XCTAssertEqual(HealthSchedule.state(dtap1, ageMonths: 1, given: [:]), .upcoming)
        XCTAssertEqual(HealthSchedule.state(dtap1, ageMonths: 2, given: [:]), .due)
        XCTAssertEqual(HealthSchedule.state(dtap1, ageMonths: 5, given: [:]), .overdue)
        XCTAssertEqual(HealthSchedule.state(dtap1, ageMonths: 5, given: ["dtap1": "2026-05-01"]), .given("2026-05-01"))
        XCTAssertTrue(HealthSchedule.dueNow(ageMonths: 2, given: [:]).contains { $0.id == "hepb1" })
        XCTAssertEqual(Set(HealthSchedule.doses.map { $0.id }).count, HealthSchedule.doses.count)
        let next = HealthSchedule.nextCheckup(birthday: "2026-03-25", today: "2026-11-25", calendar: calendar)
        XCTAssertEqual(next?.0.months, 9)
        XCTAssertEqual(next?.1, "2026-12-25")
    }

    func testMedicineTimer() {
        let tylenol = LogEntry(kidID: "a", kind: .meds, start: date("2026-11-25", 10 * 60), medicine: "Infant Tylenol")
        var status = MedicineTimer.status([tylenol], kidID: "a", now: now)
        XCTAssertEqual(status.count, 1)
        XCTAssertEqual(status.first?.rule.id, "acetaminophen")
        XCTAssertEqual(status.first?.nextOK, date("2026-11-25", 14 * 60))
        let motrin = (0..<4).map { LogEntry(kidID: "a", kind: .meds, start: date("2026-11-25", 6 * 60 + $0 * 120 - 360), medicine: "Motrin") }
        status = MedicineTimer.status(motrin, kidID: "a", now: now)
        XCTAssertEqual(status.first?.atLimit, true)
        XCTAssertEqual(status.first?.nextOK, date("2026-11-26", 0))
        XCTAssertNil(MedicineTimer.rule(for: "Amoxicillin"))
    }

    func testSickAdvice() {
        XCTAssertTrue(SickAdvice.callReasons(ageMonths: 2, temperatureF: 100.5, symptoms: [], feverHours: 1).first!.contains("under 3 months"))
        XCTAssertTrue(SickAdvice.callReasons(ageMonths: 40, temperatureF: 101, symptoms: [], feverHours: 2).isEmpty)
        XCTAssertFalse(SickAdvice.callReasons(ageMonths: 40, temperatureF: 101, symptoms: [], feverHours: 80).isEmpty)
        let readings = [LogEntry(kidID: "a", kind: .temperature, start: date("2026-11-24", 20 * 60), temperatureF: 101),
                        LogEntry(kidID: "a", kind: .temperature, start: date("2026-11-25", 8 * 60), temperatureF: 100.8)]
        XCTAssertEqual(SickAdvice.feverHours(readings, kidID: "a", now: now), 18, accuracy: 0.01)
    }

    func testStreaksPottyAndTimeTotals() {
        let brushes = ["2026-11-23", "2026-11-24"].map { LogEntry(kidID: "a", kind: .brush, start: date($0, 19 * 60)) }
        XCTAssertEqual(Teeth.brushStreak(brushes, kidID: "a", today: "2026-11-25", calendar: calendar), 2)
        let potty = [
            LogEntry(kidID: "a", kind: .potty, start: date("2026-11-24", 9 * 60), potty: .pee),
            LogEntry(kidID: "a", kind: .potty, start: date("2026-11-25", 9 * 60), potty: .pee),
            LogEntry(kidID: "a", kind: .potty, start: date("2026-11-25", 10 * 60), potty: .tried),
            LogEntry(kidID: "a", kind: .potty, start: date("2026-11-23", 9 * 60), potty: .accident),
        ]
        XCTAssertEqual(PottyStats.day(potty, kidID: "a", day: "2026-11-25", calendar: calendar), PottyStats.Day(successes: 1, tries: 1, accidents: 0))
        XCTAssertEqual(PottyStats.dryStreak(potty, kidID: "a", today: "2026-11-25", calendar: calendar), 2)
        let screen = [LogEntry(kidID: "a", kind: .screen, start: now, minutes: 30), LogEntry(kidID: "a", kind: .screen, start: now, minutes: 15)]
        let week = TimeTotals.week(screen, kidID: "a", kind: .screen, today: "2026-11-25", calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.minutes, 45)
        XCTAssertEqual(week.first?.day, "2026-11-19")
    }

    // MARK: Food planning

    func testMealPlanKeepsAllergensInRotation() {
        let kid = Kid(id: "a", name: "A", birthday: "2026-03-25", color: 0)
        let logs = [meal("2026-11-10", ["egg"]), meal("2026-11-12", ["egg"]), meal("2026-11-14", ["egg", "peanut"]),
                    meal("2026-11-20", ["salmon"], reaction: true)]
        let plan = MealPlanner.week(for: kid, logs: logs, start: "2026-11-30", now: now, calendar: calendar)
        XCTAssertEqual(plan.count, 7)
        XCTAssertEqual(plan.first?.day, "2026-11-30")
        XCTAssertTrue(plan.allSatisfy { $0.meals.count == 2 })
        let counts = MealPlanner.allergenCounts(plan)
        XCTAssertGreaterThanOrEqual(counts[.egg] ?? 0, 2)
        XCTAssertGreaterThanOrEqual(counts[.peanut] ?? 0, 2)
        // Dairy is next to start: three days in a row.
        XCTAssertGreaterThanOrEqual(counts[.milk] ?? 0, 3)
        // Fish had a reaction, so it's left out.
        XCTAssertNil(counts[.fish])
        let ids = plan.flatMap { $0.meals.flatMap { $0.foodIDs } }
        XCTAssertFalse(ids.contains("milk"))
        XCTAssertTrue(ids.allSatisfy { (FoodGuide.food($0)?.minMonths ?? 99) <= 8 })
        XCTAssertFalse(MealPlanner.groceries(plan).isEmpty)
        XCTAssertTrue(MealPlanner.slots(ageMonths: 5).isEmpty)
        XCTAssertEqual(MealPlanner.slots(ageMonths: 14).count, 4)
        // A different seed shuffles the plan.
        XCTAssertNotEqual(plan, MealPlanner.week(for: kid, logs: logs, start: "2026-11-30", seed: 1, now: now, calendar: calendar))
    }

    func testRecipesDinnersAndPickyEating() {
        XCTAssertEqual(Set(RecipeBook.all.map { $0.id }).count, RecipeBook.all.count)
        for recipe in RecipeBook.all { for id in recipe.foodIDs { XCTAssertNotNil(FoodGuide.food(id), "\(recipe.id): \(id)") } }
        for dinner in FamilyDinners.all { for id in dinner.foodIDs { XCTAssertNotNil(FoodGuide.food(id), "\(dinner.id): \(id)") } }
        XCTAssertFalse(RecipeBook.forKid(ageMonths: 7, tried: []).contains { $0.minMonths > 7 })

        let tacos = FamilyDinners.all.first { $0.id == "tacos" }!
        let adapted = FamilyDinners.adapt(tacos, ageMonths: 7, tried: ["beef"])
        XCTAssertEqual(adapted.first { $0.food.id == "beef" }?.flag, "")
        XCTAssertEqual(adapted.first { $0.food.id == "cheese" }?.flag, "New allergen")
        XCTAssertEqual(adapted.first { $0.food.id == "avocado" }?.flag, "New")
        XCTAssertEqual(adapted.first { $0.food.id == "beef" }?.howToServe, FoodGuide.food("beef")?.early)

        let logs = [meal("2026-11-01", ["banana"], liking: .loved), meal("2026-11-02", ["broccoli"], liking: .refused),
                    meal("2026-11-03", ["broccoli"], liking: .refused), meal("2026-11-04", ["pasta"]), meal("2026-11-05", ["pasta"])]
        XCTAssertEqual(PickyEater.safeFoods(logs, kidID: "a").map { $0.id }, ["banana", "pasta"])
        XCTAssertEqual(PickyEater.learningFoods(logs, kidID: "a").map { $0.food.id }, ["broccoli"])
        XCTAssertEqual(PickyEater.learningFoods(logs, kidID: "a").first?.tries, 2)
    }

    // MARK: Imports

    func testICSImport() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        DTSTART;VALUE=DATE:20261126
        DTEND;VALUE=DATE:20261128
        SUMMARY:Thanksgiving Break - No School
        END:VEVENT
        BEGIN:VEVENT
        DTSTART:20261204T150000Z
        DTEND:20261204T160000Z
        SUMMARY:Holiday sing-along\\, parents welcome
        END:VEVENT
        BEGIN:VEVENT
        DTSTART:20261211T083000
        SUMMARY:Pajama
          Day
        END:VEVENT
        END:VCALENDAR
        """
        let found = CalendarImport.ics(ics, calendar: calendar)
        XCTAssertEqual(found.map { $0.day }, ["2026-11-26", "2026-11-27", "2026-12-04", "2026-12-11"])
        XCTAssertEqual(found[0].kind, .noSchool)
        XCTAssertEqual(found[2].title, "Holiday sing-along, parents welcome")
        XCTAssertEqual(found[2].start, 15 * 60)
        XCTAssertEqual(found[3].title, "Pajama Day")
        XCTAssertEqual(found[3].start, 8 * 60 + 30)
        let events = CalendarImport.events(found, kidIDs: ["b"], existing: [OneOffEvent(title: "Pajama Day", day: "2026-12-11", kind: .special)], source: "calendar")
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.first?.source, "calendar")
    }

    func testPhotoTextImport() {
        let lines = ["Nov 27 - No School (Thanksgiving)", "12/5 Picture Day", "Dec 22-Jan 2 Winter Break",
                     "Friday, December 12: Pajama Day", "Room 3 newsletter"]
        let found = CalendarImport.lines(lines, today: "2026-11-25", calendar: calendar)
        XCTAssertEqual(found.first?.day, "2026-11-27")
        XCTAssertEqual(found.first?.title, "No School (Thanksgiving)")
        XCTAssertEqual(found.first?.kind, .noSchool)
        XCTAssertTrue(found.contains { $0.day == "2026-12-05" && $0.title == "Picture Day" })
        XCTAssertTrue(found.contains { $0.day == "2026-12-12" && $0.title == "Pajama Day" })
        let breakDays = found.filter { $0.title == "Winter Break" }.map { $0.day }
        XCTAssertEqual(breakDays.count, 12)
        XCTAssertEqual(breakDays.last, "2027-01-02")
    }

    func testDailyReportImport() {
        let text = """
        Nap 12:30 - 2:15 PM
        Diaper 10:15 AM wet
        Potty 11:00 tried
        Lunch: ate most of the pasta and peas
        Bottle 4 oz 3:00
        Played outside with chalk
        """
        let entries = DailyReport.parse(text, kidID: "b", day: "2026-11-25", calendar: calendar)
        let sleep = entries.first { $0.kind == .sleep }
        XCTAssertEqual(sleep?.start, date("2026-11-25", 12 * 60 + 30))
        XCTAssertEqual(sleep?.end, date("2026-11-25", 14 * 60 + 15))
        XCTAssertEqual(entries.first { $0.kind == .diaper }?.diaper, .wet)
        XCTAssertEqual(entries.first { $0.kind == .diaper }?.start, date("2026-11-25", 10 * 60 + 15))
        XCTAssertEqual(entries.first { $0.kind == .potty }?.potty, .tried)
        XCTAssertEqual(Set(entries.first { $0.kind == .solids }?.bites.map { $0.foodID } ?? []), ["pasta", "peas"])
        XCTAssertEqual(entries.first { $0.kind == .bottle }?.amountOz, 4)
        XCTAssertEqual(entries.first { $0.kind == .bottle }?.start, date("2026-11-25", 15 * 60))
        XCTAssertEqual(entries.first { $0.kind == .note }?.note, "From school: Played outside with chalk")
        XCTAssertTrue(entries.allSatisfy { $0.kidID == "b" })
    }

    // MARK: Sync, report, recap

    func testMergeKeepsNewerAndRespectsDeletes() {
        let a = LogEntry(id: "A", kidID: "k", kind: .bottle, start: now, amountOz: 4, updated: now)
        var newerA = a
        newerA.amountOz = 5
        newerA.updated = now.addingTimeInterval(60)
        let x = LogEntry(id: "X", kidID: "k", kind: .diaper, start: now)
        let b = LogEntry(id: "B", kidID: "k", kind: .diaper, start: now)
        let mine = FamilyState(kids: [Kid(id: "k", name: "K", birthday: "", color: 0)], logs: [a], deleted: ["X"])
        let theirs = FamilyState(kids: [Kid(id: "k", name: "K", birthday: "2026-01-01", color: 0)], logs: [newerA, x, b],
                                 routines: [RoutineItem(id: "R", title: "School", weekdays: [2], start: 480, kind: .school)])
        let result = FamilySync.merge(mine, theirs)
        XCTAssertEqual(result.state.logs.map { $0.id }.sorted(), ["A", "B"])
        XCTAssertEqual(result.state.logs.first { $0.id == "A" }?.amountOz, 5)
        XCTAssertEqual(result.newLogs, 2)
        XCTAssertEqual(result.state.routines.map { $0.id }, ["R"])
        XCTAssertEqual(result.newOther, 1)
        XCTAssertEqual(result.state.kids.first?.birthday, "2026-01-01")
        XCTAssertEqual(result.state.deleted, ["X"])
        // Merging again changes nothing.
        XCTAssertEqual(FamilySync.merge(result.state, theirs).newLogs, 0)
    }

    func testReportAndRecap() {
        let state = Sample.family(now: now, calendar: calendar)
        let baby = state.kid(Sample.babyID)!
        let html = PediatricianReport.html(kid: baby, state: state, now: now, calendar: calendar)
        XCTAssertTrue(html.contains("<h1>Griffin</h1>"))
        XCTAssertTrue(html.contains("percentile"))
        XCTAssertTrue(html.contains("Bottles"))
        let big = state.kid(Sample.bigID)!
        XCTAssertTrue(PediatricianReport.html(kid: big, state: state, now: now, calendar: calendar).contains("Milestones to talk about"))

        let recap = Recap.month("2026-11", kid: baby, state: state, calendar: calendar)
        XCTAssertEqual(recap.title, "November 2026")
        XCTAssertEqual(recap.firsts.count, 2)
        XCTAssertGreaterThan(recap.newFoods.count, 10)
        XCTAssertNotNil(recap.lovedFood)
        XCTAssertFalse(Recap.memories(state.logs, kidID: nil).isEmpty)
    }

    func testMilestoneActivitiesFitTheAge() {
        let state = Sample.family(now: now, calendar: calendar)
        let picks = MilestoneActivities.picks(ageMonths: 8, statuses: state.milestones[Sample.babyID] ?? [:])
        XCTAssertFalse(picks.isEmpty)
        XCTAssertTrue(picks.allSatisfy { pick in pick.activities.allSatisfy { $0.fits(ageMonths: 8) } })
        for link in MilestoneActivities.links { for id in link.activities { XCTAssertNotNil(ActivityLibrary.activity(id), id) } }
    }

    func testLeaveTime() {
        let state = FamilyState(
            kids: [Kid(id: "big", name: "Big", birthday: "2023-06-01", color: 1)],
            routines: [
                RoutineItem(id: "drop", title: "Drop-off", kidIDs: ["big"], weekdays: [4], start: 495, kind: .dropoff),
                RoutineItem(id: "school", title: "Preschool", kidIDs: ["big"], weekdays: [4, 6], start: 510, kind: .school),
            ],
            events: [OneOffEvent(title: "No school", day: "2026-12-02", kind: .noSchool)])
        let wednesday = Agenda.leave(on: "2026-11-25", state: state, travelMinutes: 15, calendar: calendar)
        XCTAssertEqual(wednesday?.minute, 480)
        XCTAssertEqual(wednesday?.entry.id, "drop")
        // Friday has no drop-off routine, so school's start is used.
        XCTAssertEqual(Agenda.leave(on: "2026-11-27", state: state, travelMinutes: 15, calendar: calendar)?.minute, 495)
        XCTAssertNil(Agenda.leave(on: "2026-12-02", state: state, travelMinutes: 15, calendar: calendar))
        XCTAssertNil(Agenda.leave(on: "2026-11-26", state: state, travelMinutes: 15, calendar: calendar))
    }
}
