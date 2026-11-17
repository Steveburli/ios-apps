import SwiftUI
import EventKit
import EventKitUI
import UniformTypeIdentifiers
import MutualKit

/// A card as a calendar invite (.ics) to send to family, who tap it to add
/// the event to their own calendar, Google included.
struct EventInvite: Transferable {
    let card: Card

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .calendarEvent) { invite in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(invite.card.id, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(CalendarPlan.fileName(for: invite.card))
            let text = CalendarPlan.ics(for: invite.card, start: CalendarPlan.start(for: invite.card))
            try text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

/// The iPhone's own New Event screen, filled in from a card. The person picks
/// the date and calendar and saves it themselves, so Mutual never needs
/// access to anyone's calendar.
struct EventEditor: UIViewControllerRepresentable {
    let card: Card
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.title = card.title
        event.notes = CalendarPlan.notes(for: card)
        if !card.link.isEmpty, let url = URL(string: card.link) {
            event.url = url
        }
        // The card's own time, or next Friday at 7 PM for them to change. Two hours.
        let start = CalendarPlan.start(for: card)
        event.startDate = start
        event.endDate = start.addingTimeInterval(CalendarPlan.length)

        // A plan is one event for the whole night: from the first stop's time
        // to two hours after the last, with every stop in the notes.
        if let plan = card.plan, !plan.stops.isEmpty {
            let times = plan.stops.compactMap(\.minutes)
            // The day comes from the card's time, or next Friday (`start` above).
            if let first = times.first, let day = Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: start) {
                let last = max(times.last ?? first, first)
                event.startDate = day.addingTimeInterval(TimeInterval(first * 60))
                event.endDate = day.addingTimeInterval(TimeInterval((last + 120) * 60))
            } else {
                event.endDate = start.addingTimeInterval(3 * 3600)
            }
            let stop = plan.stops[0]
            event.location = [stop.place, stop.address].filter { !$0.isEmpty }.joined(separator: ", ")
            event.notes = [card.subtitle, plan.summary, card.details].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }

        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void

        init(onDone: @escaping () -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
