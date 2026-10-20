import Foundation
@testable import DoThisNowKit

/// UTC, English, so day math and labels don't depend on the machine.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}()

let formats = Formats(calendar: utc)

/// Wednesday, Oct 14 2026, 10:00.
let wednesday10am = utc.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 10))!

func day(_ month: Int, _ day: Int) -> CalendarDay {
    CalendarDay(year: 2026, month: month, day: day)
}

func daysAgo(_ days: Double, from now: Date = wednesday10am) -> Date {
    now.addingTimeInterval(-days * 86_400)
}

func makeTask(_ title: String, _ kind: TaskKind = .task, tier: Int = 3, places: [Place] = [.home],
              estimate: Int = 30, created: Date = daysAgo(1), _ configure: (inout TaskItem) -> Void = { _ in }) -> TaskItem {
    var task = TaskItem(id: title, title: title, created: created)
    task.kind = kind
    task.tier = tier
    task.places = places
    task.estimate = estimate
    configure(&task)
    return task
}

func engine(_ state: PlannerState, now: Date = wednesday10am) -> Engine {
    Engine(state: state, now: now, formats: formats)
}
