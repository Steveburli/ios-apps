import SwiftUI
import DoThisNowKit

/// Moving between days on the Day tab: swipes, the Today button and the week view.
extension AppModel {
    /// The last day the Day tab can show.
    var lastDayAhead: CalendarDay { today.adding(days: Self.daysAhead, calendar: calendar) }

    func canShow(_ day: CalendarDay) -> Bool {
        day >= today && day <= lastDayAhead
    }

    /// The Monday that starts the week holding `day`. Weeks start on Monday.
    func weekStart(of day: CalendarDay) -> CalendarDay {
        // weekdayIndex: 0 is Sunday, 1 is Monday … 6 is Saturday.
        let back = (day.weekdayIndex(calendar: calendar) + 6) % 7
        return day.adding(days: -back, calendar: calendar)
    }

    /// The seven days of the week holding `day`, Monday first.
    func week(of day: CalendarDay) -> [CalendarDay] {
        let monday = weekStart(of: day)
        return (0..<7).map { monday.adding(days: $0, calendar: calendar) }
    }

    /// Back to today, scrolled to now.
    func goToToday() {
        refreshNow()
        daySlideEdge = .leading
        dayShown = today
        scrollDayToNow = true
    }

    /// The Week button: shows the whole week, or goes back to the day.
    func setWeekShown(_ on: Bool) {
        weekShown = on
        if on { dayPage = .timeline } else { scrollDayToNow = true }
    }

    /// Tapping a day in the week view opens it on the Day.
    func openDayFromWeek(_ day: CalendarDay) {
        guard canShow(day) else { return }
        daySlideEdge = day < dayShown ? .leading : .trailing
        dayShown = day
        weekShown = false
        scrollDayToNow = true
    }

    /// Whether the week view can go `offset` weeks back or ahead.
    func canShowWeek(offset: Int) -> Bool {
        let monday = weekStart(of: dayShown).adding(days: 7 * offset, calendar: calendar)
        let sunday = monday.adding(days: 6, calendar: calendar)
        return sunday >= today && monday <= lastDayAhead
    }

    /// Moves the week view a week back or ahead. The day shown becomes that
    /// week's first day the Day tab can show.
    func showWeek(offset: Int) {
        guard canShowWeek(offset: offset) else { return }
        let monday = weekStart(of: dayShown).adding(days: 7 * offset, calendar: calendar)
        daySlideEdge = offset < 0 ? .leading : .trailing
        dayShown = max(monday, today)
    }
}
