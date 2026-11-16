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
