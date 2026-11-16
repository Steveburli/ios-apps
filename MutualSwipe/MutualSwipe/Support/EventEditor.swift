import SwiftUI
import EventKit
import EventKitUI
import MutualKit

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
        event.notes = [card.subtitle, card.details].filter { !$0.isEmpty }.joined(separator: "\n\n")
        if !card.link.isEmpty, let url = URL(string: card.link) {
            event.url = url
        }
        // Next Friday at 7 PM, two hours. They'll change it.
        let calendar = Calendar.current
        let friday = calendar.nextDate(after: Date(), matching: DateComponents(hour: 19, minute: 0, weekday: 6),
                                       matchingPolicy: .nextTime) ?? Date().addingTimeInterval(86_400)
        event.startDate = friday
        event.endDate = friday.addingTimeInterval(2 * 3600)

        // A plan is one event for the whole night: from the first stop's time
        // to two hours after the last, with every stop in the notes.
        if let plan = card.plan, !plan.stops.isEmpty {
            let times = plan.stops.compactMap(\.minutes)
            if let first = times.first, let day = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: friday) {
                let last = max(times.last ?? first, first)
                event.startDate = day.addingTimeInterval(TimeInterval(first * 60))
                event.endDate = day.addingTimeInterval(TimeInterval((last + 120) * 60))
            } else {
                event.endDate = friday.addingTimeInterval(3 * 3600)
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
