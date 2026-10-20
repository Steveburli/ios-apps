import SwiftUI
import DoThisNowKit

struct EventFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let original: PlannerEvent?
    @State private var title: String
    @State private var date: Date
    @State private var start: Int
    @State private var end: Int
    @State private var minStay: Int
    @State private var travel: Int
    @State private var arrive: Int
    @State private var overWork: Bool
    @State private var error: String?
    @State private var confirmingDelete = false
    @FocusState private var titleFocused: Bool

    init(event: PlannerEvent?, day: CalendarDay) {
        original = event
        _title = State(initialValue: event?.title ?? "")
        _date = State(initialValue: (event?.day ?? day).startDate(calendar: .autoupdatingCurrent))
        _start = State(initialValue: event?.start ?? 18 * 60)
        _end = State(initialValue: event?.end ?? 19 * 60)
        _minStay = State(initialValue: event?.minStay ?? 60)
        _travel = State(initialValue: event?.travel ?? 15)
        _arrive = State(initialValue: event?.arrive ?? event?.start ?? 18 * 60)
        _overWork = State(initialValue: event?.overWork ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What is it?") {
                    TextField("e.g. Dinner at Alex’s", text: $title)
                        .focused($titleFocused)
                }
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    MinuteOfDayPicker(title: "Starts", minutes: $start)
                    MinuteOfDayPicker(title: "Ends", minutes: $end)
                }
                Section {
                    MinuteStepper(title: "Minimum time you need to be there", minutes: $minStay, range: 5...720)
                    MinuteStepper(title: "Travel time each way", minutes: $travel, range: 0...240)
                }
                Section {
                    MinuteOfDayPicker(title: "When do you want to arrive?", minutes: $arrive)
                } footer: {
                    Text("You can also drag it on the Day view.")
                }
                Section {
                    Toggle("If it overlaps work, I’ll take time off for it", isOn: $overWork)
                }
                if let error {
                    Section {
                        Text(error)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.bad)
                    }
                }
                if original != nil {
                    Section {
                        Button("Delete event", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .tint(Theme.accent)
            .navigationTitle(original == nil ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(original == nil ? "Add event" : "Save") { save() }
                        .fontWeight(.bold)
                }
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = original?.id { model.deleteEvent(id) }
                }
            }
            .onChange(of: start) { old, new in
                // Keep the arrival on the start time unless it was moved.
                if arrive == old || arrive < new { arrive = new }
            }
            .onAppear {
                if original == nil { titleFocused = true }
            }
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            error = "Give the event a name first."
            titleFocused = true
            return
        }
        guard end > start else {
            error = "The end time needs to be after the start time."
            return
        }
        let stay = max(5, min(end - start, minStay))
        let arrival = max(start, min(end - stay, arrive))
        var event = original ?? PlannerEvent(title: name, day: CalendarDay(date, calendar: model.calendar),
                                             start: start, end: end, minStay: stay, travel: travel)
        event.title = name
        event.day = CalendarDay(date, calendar: model.calendar)
        event.start = start
        event.end = end
        event.minStay = stay
        event.travel = max(0, travel)
        event.arrive = arrival == start ? nil : arrival
        event.overWork = overWork
        event.isExample = false
        model.save(event)
    }
}
