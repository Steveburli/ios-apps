import SwiftUI
import LittlesKit

struct RoutineEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var item: RoutineItem
    let isNew: Bool
    @State private var hasEnd: Bool
    @State private var hasUntil: Bool

    init(item: RoutineItem, isNew: Bool) {
        _item = State(initialValue: item)
        self.isNew = isNew
        _hasEnd = State(initialValue: item.end != nil)
        _hasUntil = State(initialValue: !item.until.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title, like Preschool", text: $item.title)
                    Picker("Kind", selection: $item.kind) {
                        ForEach(RoutineKind.allCases) { Text("\($0.emoji) \($0.title)").tag($0) }
                    }
                }
                Section("Who") {
                    KidsToggle(kidIDs: $item.kidIDs)
                }
                Section("Days") {
                    WeekdayPicker(days: $item.weekdays)
                }
                Section("Time") {
                    MinutesPicker(title: "Starts", minutes: $item.start)
                    Toggle("Has an end time", isOn: $hasEnd)
                    if hasEnd {
                        MinutesPicker(title: "Ends", minutes: Binding(get: { item.end ?? item.start + 60 }, set: { item.end = $0 }))
                    }
                    Picker("Remind me", selection: $item.remind) {
                        Text("No reminder").tag(Int?.none)
                        Text("At the time").tag(Int?.some(0))
                        ForEach([10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) minutes before").tag(Int?.some($0)) }
                    }
                }
                Section {
                    TextField("Place", text: $item.place)
                    TextField("Note, like teacher or room", text: $item.note)
                }
                Section {
                    Toggle("Ends on a date", isOn: $hasUntil)
                    if hasUntil {
                        DatePicker("Last day", selection: Binding(
                            get: { Dates.date(item.until) ?? Date().addingTimeInterval(180 * 86_400) },
                            set: { item.until = Dates.key($0) }
                        ), displayedComponents: .date)
                    }
                } footer: {
                    Text("For a school year, set the last day so it drops off the schedule in summer.")
                }
                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) {
                            model.deleteRoutine(item.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New routine" : "Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = item
                        saved.title = saved.title.trimmingCharacters(in: .whitespaces)
                        if saved.title.isEmpty { saved.title = saved.kind.title }
                        if !hasEnd { saved.end = nil } else if saved.end == nil { saved.end = saved.start + 60 }
                        if !hasUntil { saved.until = "" } else if saved.until.isEmpty {
                            saved.until = Dates.key(Date().addingTimeInterval(180 * 86_400))
                        }
                        model.saveRoutine(saved)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(item.weekdays.isEmpty)
                }
            }
        }
    }
}

struct EventEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var event: OneOffEvent
    let isNew: Bool
    @State private var timed: Bool

    init(event: OneOffEvent, isNew: Bool) {
        _event = State(initialValue: event)
        self.isNew = isNew
        _timed = State(initialValue: event.start != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title, like Pajama day", text: $event.title)
                    Picker("Kind", selection: $event.kind) {
                        ForEach(EventKind.allCases) { Text("\($0.emoji) \($0.title)").tag($0) }
                    }
                } footer: {
                    if event.kind == .noSchool {
                        Text("Preschool, drop-off and pickup are crossed off that day.")
                    }
                }
                Section("Who") {
                    KidsToggle(kidIDs: $event.kidIDs)
                }
                Section("When") {
                    DatePicker("Day", selection: Binding(
                        get: { Dates.date(event.day) ?? Date() },
                        set: { event.day = Dates.key($0) }
                    ), displayedComponents: .date)
                    Toggle("At a set time", isOn: $timed)
                    if timed {
                        MinutesPicker(title: "Starts", minutes: Binding(get: { event.start ?? 9 * 60 }, set: { event.start = $0 }))
                    }
                }
                if event.kind == .party {
                    Section("Party") {
                        Picker("RSVP", selection: $event.rsvp) {
                            Text("Not yet").tag("")
                            Text("Going").tag("yes")
                            Text("Maybe").tag("maybe")
                            Text("Can't go").tag("no")
                        }
                        .pickerStyle(.segmented)
                        TextField("Gift idea", text: $event.gift)
                        Button {
                            if !event.gift.isEmpty { model.addShopping(event.gift, list: "Party") }
                        } label: {
                            Label("Add the gift to the shopping list", systemImage: "cart.badge.plus")
                        }
                        .disabled(event.gift.isEmpty)
                    }
                }
                Section {
                    TextField("Bring or wear, like $5 for the book fair", text: $event.bring)
                    TextField("Note", text: $event.note, axis: .vertical)
                } footer: {
                    Text("What to bring shows up on that day's pack list.")
                }
                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) {
                            model.deleteEvent(event.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New event" : "Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = event
                        saved.title = saved.title.trimmingCharacters(in: .whitespaces)
                        if saved.title.isEmpty { saved.title = saved.kind.title }
                        if !timed { saved.start = nil } else if saved.start == nil { saved.start = 9 * 60 }
                        model.saveEvent(saved)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

struct PackItemEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var item: PackItem
    let isNew: Bool

    init(item: PackItem, isNew: Bool) {
        _item = State(initialValue: item)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Like Water bottle or Library book", text: $item.title)
                    Picker("For", selection: $item.kidID) {
                        ForEach(model.state.kids) { Text($0.name).tag($0.id) }
                    }
                }
                Section {
                    WeekdayPicker(days: $item.weekdays)
                } header: {
                    Text("Days")
                } footer: {
                    Text("Leave all days off for every school day. Only days with preschool count.")
                }
                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) {
                            model.deletePackItem(item.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Something to pack" : "Pack item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.savePackItem(item)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
