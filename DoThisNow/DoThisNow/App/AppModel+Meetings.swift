import SwiftUI
import DoThisNowKit

/// Work meetings from a locked calendar (Alignops to start). They keep their
/// exact times on the Day, and tasks go around them.
extension AppModel {
    /// Reads the locked calendars again and brings the saved meetings in line.
    func refreshMeetings() {
        guard !Screenshots.isActive, state.meetingSettings.on else { return }
        let source = MeetingsSource.shared
        guard source.isAuthorized else {
            meetingCalendars = []
            meetingsProblem = "Do This Now can’t see your calendars. Turn on Calendars for Do This Now in the Settings app, under Apps."
            return
        }
        meetingCalendars = source.calendars()
        guard let fresh = source.fetch(settings: state.meetingSettings, calendar: calendar) else {
            meetingsProblem = "Couldn’t read your calendar just now. I’ll try again next time you open the app."
            return
        }
        meetingsProblem = lockedCalendarNames.isEmpty
            ? "No locked calendar yet. Pick your work calendar below."
            : nil
        if state.syncMeetings(fresh) { commit() }
    }

    /// The names of the calendars whose meetings are locked right now.
    var lockedCalendarNames: [String] {
        meetingCalendars.filter { state.meetingSettings.locks(calendarID: $0.id, name: $0.name) }.map(\.name)
    }

    /// Turns locked meetings on (asking for calendar access the first time) or off.
    func setMeetingsOn(_ on: Bool) async {
        guard on else {
            state.meetingSettings.on = false
            state.meetings = []
            meetingsProblem = nil
            commit()
            return
        }
        let granted = await MeetingsSource.shared.requestAccess()
        state.meetingSettings.on = true
        commit()
        if granted {
            refreshMeetings()
        } else {
            meetingsProblem = "Do This Now can’t see your calendars. Turn on Calendars for Do This Now in the Settings app, under Apps."
            show("Turn on Calendars for Do This Now in the Settings app, under Apps.")
        }
    }

    /// Locks or unlocks one calendar's meetings. The first pick replaces the
    /// "anything named Alignops" default with your own list.
    func setCalendarLocked(_ list: SourceList, _ locked: Bool) {
        var ids = state.meetingSettings.calendarIDs ?? lockedCalendars().map(\.id)
        ids.removeAll { $0 == list.id }
        if locked { ids.append(list.id) }
        state.meetingSettings.calendarIDs = ids
        commit()
        refreshMeetings()
    }

    private func lockedCalendars() -> [SourceList] {
        meetingCalendars.filter { state.meetingSettings.locks(calendarID: $0.id, name: $0.name) }
    }
}
