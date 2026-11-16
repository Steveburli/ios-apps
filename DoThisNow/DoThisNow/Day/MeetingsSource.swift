import EventKit
import DoThisNowKit

/// Meetings from your calendars, read with EventKit. Only calendars you lock
/// (Alignops to start) come in, and nothing is ever written back.
final class MeetingsSource: @unchecked Sendable {
    static let shared = MeetingsSource()

    private let store = EKEventStore()

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        if isAuthorized { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    func calendars() -> [AppModel.SourceList] {
        guard isAuthorized else { return [] }
        return store.calendars(for: .event)
            .map { AppModel.SourceList(id: $0.calendarIdentifier, name: $0.title) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Timed events on the locked calendars from yesterday through the next
    /// two weeks, or nil when the calendar can't be read. All-day events are
    /// left out: they have no start and end to protect.
    func fetch(settings: MeetingSettings, calendar: Calendar) -> [Meeting]? {
        guard isAuthorized else { return nil }
        let locked = store.calendars(for: .event).filter {
            settings.locks(calendarID: $0.calendarIdentifier, name: $0.title)
        }
        guard !locked.isEmpty else { return [] }
        let today = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -1, to: today),
              let to = calendar.date(byAdding: .day, value: 15, to: today) else { return nil }
        store.refreshSourcesIfNecessary()
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: locked)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && $0.endDate > $0.startDate && !Self.declined($0) }
            .map { event in
                Meeting.from(eventID: event.calendarItemIdentifier, title: event.title ?? "",
                             start: event.startDate, end: event.endDate,
                             calendarName: event.calendar?.title ?? "", calendar: calendar)
            }
    }

    /// Meetings you said no to don't hold your time.
    private static func declined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }
}
