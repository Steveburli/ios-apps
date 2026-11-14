import SwiftUI
import EventKit
import MutualKit

/// Puts every Super match and Match from a deck on one calendar in one tap.
/// The person picks the calendar (a Google or family calendar already on the
/// phone shows up here), checks the times, and adds them. Ones already on
/// that calendar are left unticked so nothing lands twice.
struct CalendarSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let deckID: String

    private enum Access { case asking, granted, denied }

    @State private var eventStore = EKEventStore()
    @State private var access: Access = .asking
    @State private var calendars: [EKCalendar] = []
    @State private var calendarID: String?
    /// Card ID → the time it goes on the calendar.
    @State private var times: [String: Date] = [:]
    /// Ticked cards. Nil until the first calendar is chosen.
    @State private var chosen: Set<String>?

    var body: some View {
        NavigationStack {
            Group {
                if let deck = store.decks[deckID] {
                    switch access {
                    case .asking: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .denied: denied
                    case .granted: content(deck)
                    }
                } else {
                    ContentUnavailableView("This deck was deleted", systemImage: "rectangle.stack.badge.minus")
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Add to calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await askForAccess() }
    }

    // MARK: Screens

    private var denied: some View {
        ScrollView {
            Panel {
                Text("Mutual can’t see your calendars").font(Theme.display(18, weight: .bold))
                Text("To add every match at once, turn on Full Access in Settings → Apps → Mutual → Calendars. You can still add matches one at a time from each card, with no access needed.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.mutual())
            }
            .padding(16)
        }
    }

    private func content(_ deck: Deck) -> some View {
        let me = session.me(in: deck.groupID, store: store)
        let state = store.liveState(of: deck.id, me: me, vetting: !session.showsRound(deck))
        let matches = CalendarPlan.matches(in: state)
        let calendar = calendars.first { $0.calendarIdentifier == calendarID }
        let picked = matches.filter { chosen?.contains($0.id) ?? false }

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if matches.isEmpty {
                    Panel {
                        Text("No matches yet").font(Theme.display(18, weight: .bold))
                        Text("Only Super matches and Matches go on the calendar, once at least two people have swiped.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                } else if calendars.isEmpty {
                    Panel {
                        Text("No calendars to add to").font(Theme.display(18, weight: .bold))
                        Text("Add a calendar in the Calendar app, or add your Google account in Settings → Apps → Calendar → Calendar Accounts.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Panel {
                        Picker("Calendar", selection: Binding(get: { calendarID ?? "" }, set: { choose($0, deck: deck, matches: matches) })) {
                            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                                Text("\(calendar.title) · \(calendar.source?.title ?? "")").tag(calendar.calendarIdentifier)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .foregroundStyle(Theme.ink)
                        Text("A Google calendar you share with family works here if it’s added to this iPhone.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }

                    ForEach(matches) { card in
                        row(card, state: state, calendar: calendar, canWrite: store.canWrite(deck.groupID))
                    }

                    Text(store.canWrite(deck.groupID)
                         ? "Changing a time here saves it on the card for everyone."
                         : "Times you change here are only for your calendar.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)

                    Button {
                        add(picked, to: calendar, canWrite: store.canWrite(deck.groupID))
                    } label: {
                        Label(picked.isEmpty ? "Nothing ticked" : "Add \(picked.count) to \(calendar?.title ?? "calendar")",
                              systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(.mutual(wide: true))
                    .disabled(picked.isEmpty || calendar == nil)
                }
            }
            .padding(16)
        }
        .onAppear { if chosen == nil, let id = calendarID { choose(id, deck: deck, matches: matches) } }
    }

    private func row(_ card: Card, state: DeckState, calendar: EKCalendar?, canWrite: Bool) -> some View {
        let isOn = chosen?.contains(card.id) ?? false
        let start = times[card.id] ?? CalendarPlan.start(for: card)
        let already = calendar.map { isOnCalendar(card, start: start, calendar: $0) } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { isOn }, set: { on in
                var set = chosen ?? []
                if on { set.insert(card.id) } else { set.remove(card.id) }
                chosen = set
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(already ? "Already on this calendar" : state.verdict(for: card).label)
                        .font(.footnote)
                        .foregroundStyle(already ? Vote.like.color : Theme.muted)
                }
            }
            .tint(Theme.accent)
            DatePicker("When", selection: Binding(get: { start }, set: { times[card.id] = $0 }))
                .font(.subheadline)
                .foregroundStyle(card.startsAt == nil && times[card.id] == nil ? Theme.muted : Theme.ink)
            if card.startsAt == nil && times[card.id] == nil {
                Text("No time on this card yet, so it starts next Friday at 7 PM. Change it here.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isOn ? Theme.accent : Theme.line))
    }

    // MARK: Calendar work

    private func askForAccess() async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            loadCalendars()
        case .notDetermined:
            let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
            if granted { loadCalendars() } else { access = .denied }
        default:
            access = .denied
        }
    }

    private func loadCalendars() {
        calendars = eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title) }
        let groupID = store.decks[deckID]?.groupID ?? ""
        let remembered = UserDefaults.standard.string(forKey: Self.key(groupID))
        calendarID = calendars.first { $0.calendarIdentifier == remembered }?.calendarIdentifier
            ?? eventStore.defaultCalendarForNewEvents.flatMap { def in
                calendars.first { $0.calendarIdentifier == def.calendarIdentifier }?.calendarIdentifier
            }
            ?? calendars.first?.calendarIdentifier
        access = .granted
    }

    /// Picks a calendar, remembers it for the group, and ticks every match
    /// that isn't on it yet.
    private func choose(_ id: String, deck: Deck, matches: [Card]) {
        calendarID = id
        UserDefaults.standard.set(id, forKey: Self.key(deck.groupID))
        guard let calendar = calendars.first(where: { $0.calendarIdentifier == id }) else { return }
        chosen = Set(matches.filter { card in
            !isOnCalendar(card, start: times[card.id] ?? CalendarPlan.start(for: card), calendar: calendar)
        }.map(\.id))
    }

    /// An event with the same title within a day of this time.
    private func isOnCalendar(_ card: Card, start: Date, calendar: EKCalendar) -> Bool {
        let predicate = eventStore.predicateForEvents(withStart: start.addingTimeInterval(-86_400),
                                                      end: start.addingTimeInterval(86_400), calendars: [calendar])
        let title = card.title.lowercased()
        return eventStore.events(matching: predicate).contains { ($0.title ?? "").lowercased() == title }
    }

    private func add(_ cards: [Card], to calendar: EKCalendar?, canWrite: Bool) {
        guard let calendar else { return }
        var added = 0
        for card in cards {
            let start = times[card.id] ?? CalendarPlan.start(for: card)
            let event = EKEvent(eventStore: eventStore)
            event.calendar = calendar
            event.title = card.title
            event.notes = CalendarPlan.notes(for: card)
            if !card.link.isEmpty, let url = URL(string: card.link) { event.url = url }
            event.startDate = start
            event.endDate = start.addingTimeInterval(CalendarPlan.length)
            do {
                try eventStore.save(event, span: .thisEvent, commit: false)
                added += 1
                if canWrite, let picked = times[card.id], picked != card.startsAt {
                    store.setTime(picked, card: card.id)
                }
            } catch {
                continue
            }
        }
        do {
            try eventStore.commit()
        } catch {
            eventStore.reset()
            session.show("Couldn’t add to \(calendar.title). Try again.")
            return
        }
        session.show(added == cards.count
                     ? "Added \(added) to \(calendar.title)"
                     : "Added \(added) of \(cards.count) to \(calendar.title)")
        dismiss()
    }

    private static func key(_ groupID: String) -> String { "calendar-" + groupID }
}
