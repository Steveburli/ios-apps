import SwiftUI
import MapKit
import DoThisNowKit

enum TripSheet: Identifiable {
    case newTrip
    case editTrip(String)
    case newStop(String, onDay: Bool)
    case editStop(String)
    case catchUp(String, TripPlanner.CatchUp)

    var id: String {
        switch self {
        case .newTrip: return "new-trip"
        case .editTrip(let id): return "trip-" + id
        case .newStop(let id, let onDay): return "new-stop-\(id)-\(onDay)"
        case .editStop(let id): return "stop-" + id
        case .catchUp(let id, let plan): return "catch-up-\(id)-\(plan.now)"
        }
    }
}

struct TripSheetContent: View {
    let sheet: TripSheet

    var body: some View {
        switch sheet {
        case .newTrip:
            TripFormView(tripID: nil)
        case .editTrip(let id):
            TripFormView(tripID: id)
        case .newStop(let tripID, let onDay):
            StopFormView(stopID: nil, tripID: tripID, startOnDay: onDay)
        case .editStop(let id):
            StopFormView(stopID: id, tripID: TripStore.shared.stop(id)?.tripID ?? "", startOnDay: true)
        case .catchUp(let tripID, let plan):
            CatchUpView(tripID: tripID, plan: plan)
        }
    }
}

// MARK: - Trip

private struct TripFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tripID: String?
    @State private var name = ""
    @State private var date = Date()
    @State private var start = 600
    @State private var end = 1320
    @State private var walk = 30
    @State private var loaded = false
    @State private var confirmDelete = false

    private var store: TripStore { .shared }
    private var entry: TripStore.TripEntry? { tripID.flatMap { store.trips[$0] } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Julia’s birthday", text: $name)
                        .font(.body.weight(.semibold))
                }
                Section("When") {
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                    MinuteOfDayPicker(title: "We get there about", minutes: $start)
                    MinuteOfDayPicker(title: "Wrap up by", minutes: $end)
                }
                Section {
                    ChoiceChips(options: [15, 20, 30, 45].map { ($0, "\($0) min") }, selection: $walk)
                } header: {
                    Text("Walk if it takes up to")
                } footer: {
                    Text("Anything longer, the plan drives.")
                }
                if let entry {
                    Section {
                        if entry.trip.arrivedMinute != nil {
                            Button("Start from the planned time again") {
                                var trip = entry.trip
                                trip.arrivedMinute = nil
                                trip.resumeMinute = nil
                                trip.resumeStopID = nil
                                store.update(trip)
                                dismiss()
                            }
                        }
                        Button(entry.isOwned ? "Delete trip" : "Leave trip", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .disabled(entry?.readOnly == true)
            .navigationTitle(tripID == nil ? "New trip" : "Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(entry?.readOnly == true)
                }
            }
            .confirmationDialog(entry?.isOwned == false ? "Leave this trip?" : "Delete this trip?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button(entry?.isOwned == false ? "Leave trip" : "Delete trip", role: .destructive) {
                    if let tripID { store.removeTrip(tripID) }
                    dismiss()
                }
            } message: {
                Text(entry?.isShared == true && entry?.isOwned == true
                     ? "It’s removed for everyone you shared it with too."
                     : "Its stops and wish list go too.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let trip = entry?.trip else {
            date = model.today.adding(days: 1, calendar: model.calendar).startDate(calendar: model.calendar)
            return
        }
        name = trip.name
        date = trip.day.startDate(calendar: model.calendar)
        start = trip.startMinute
        end = trip.endMinute
        walk = trip.walkLimit
    }

    private func save() {
        let day = CalendarDay(date, calendar: model.calendar)
        var trip = entry?.trip ?? store.createTrip(name: name, day: day, startMinute: start)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { trip.name = String(trimmed.prefix(60)) }
        trip.day = day
        trip.startMinute = start
        trip.endMinute = max(end, start + 30)
        trip.walkLimit = walk
        store.update(trip)
        store.selectedTripID = trip.id
        dismiss()
    }
}

// MARK: - Stop

private struct StopFormView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let stopID: String?
    let tripID: String
    let startOnDay: Bool

    @State private var title = ""
    @State private var address = ""
    @State private var coordinate: Coordinate?
    @State private var kind = StopKind.sight
    @State private var stay = StopKind.sight.defaultMinutes
    @State private var isFixed = false
    @State private var fixedMinute = 720
    @State private var priority = StopPriority.want
    @State private var onDay = true
    @State private var note = ""
    @State private var loaded = false
    @State private var search = PlaceSearch()
    @State private var finding = false

    private var store: TripStore { .shared }
    private var canWrite: Bool { store.canWrite(tripID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it, like Lunch or The show", text: $title)
                        .font(.body.weight(.semibold))
                }
                Section("Where") {
                    if coordinate != nil {
                        HStack {
                            Label(address.isEmpty ? "Picked on the map" : address, systemImage: "mappin.circle.fill")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button("Change") {
                                coordinate = nil
                                address = ""
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    } else {
                        TextField("Search a place or address", text: $search.query)
                            .textInputAutocapitalization(.words)
                        if finding { ProgressView() }
                        ForEach(search.results, id: \.self) { result in
                            Button { pick(result) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title).foregroundStyle(Theme.ink)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle).font(.caption).foregroundStyle(Theme.ink3)
                                    }
                                }
                            }
                        }
                        if search.results.isEmpty {
                            Text("With an address, the plan shows travel time and puts it on the map.")
                                .font(.footnote)
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                }
                Section("Kind") {
                    ChoiceChips(options: StopKind.allCases.map { ($0, $0.label) }, selection: $kind)
                }
                Section("Time there") {
                    ChoiceChips(options: [15, 30, 45, 60, 90, 120, 180].map { ($0, TimeText.duration($0)) }, selection: $stay)
                    MinuteStepper(title: "Time there", minutes: $stay, range: 5...720)
                }
                Section {
                    Toggle("Set time", isOn: $isFixed)
                    if isFixed {
                        MinuteOfDayPicker(title: "At", minutes: $fixedMinute)
                    }
                } footer: {
                    Text("For a show, check-in or a booking. It keeps its time, and the plan warns you if you’d be late.")
                }
                if !isFixed {
                    Section("How much do you want this?") {
                        ChoiceChips(options: [3, 2, 1].map { ($0, PriorityText.label($0)) }, selection: $priority)
                    }
                    Section {
                        Picker("Put it on", selection: $onDay) {
                            Text("The day").tag(true)
                            Text("Wish list").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("Note") {
                    TextField("Optional, like the booking name", text: $note, axis: .vertical)
                }
                if stopID != nil && canWrite {
                    Section {
                        Button("Delete stop", role: .destructive) {
                            if let stopID { store.deleteStop(stopID) }
                            dismiss()
                        }
                    }
                }
            }
            .disabled(!canWrite)
            .navigationTitle(stopID == nil ? (startOnDay ? "New stop" : "Add to wish list") : "Stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canWrite || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: kind) { old, new in
                // Follow the kind's usual length until you pick your own.
                if stay == old.defaultMinutes { stay = new.defaultMinutes }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        onDay = startOnDay
        if let planner = store.planner(for: tripID) {
            search.focus(on: planner.stops.compactMap(\.coordinate))
            fixedMinute = planner.trip.startMinute + 120
        }
        guard let stopID, let stop = store.stop(stopID) else { return }
        title = stop.title
        address = stop.address
        coordinate = stop.coordinate
        kind = stop.kind
        stay = stop.stayMinutes
        isFixed = stop.isFixed
        fixedMinute = stop.fixedMinute ?? fixedMinute
        priority = stop.priority
        onDay = stop.onDay
        note = stop.note
    }

    private func pick(_ result: MKLocalSearchCompletion) {
        finding = true
        Task {
            defer { finding = false }
            guard let place = await search.resolve(result) else {
                model.show("Couldn’t find that place. Check your connection and try again.")
                return
            }
            coordinate = place.coordinate
            address = place.address
            if title.trimmingCharacters(in: .whitespaces).isEmpty { title = place.name }
            search.query = ""
        }
    }

    private func save() {
        var stop = stopID.flatMap { store.stop($0) } ?? TripStop(tripID: tripID, title: "")
        stop.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        stop.address = address
        stop.coordinate = coordinate
        stop.kind = kind
        stop.stayMinutes = stay
        stop.fixedMinute = isFixed ? fixedMinute : nil
        stop.priority = priority
        stop.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        // Set times always sit on the day.
        let wantsDay = isFixed || onDay
        if stopID != nil && stop.onDay != wantsDay {
            store.save(stop)
            store.setOnDay(stop.id, wantsDay)
        } else {
            stop.onDay = wantsDay
            store.save(stop)
        }
        dismiss()
    }
}

// MARK: - We're off schedule

private struct CatchUpView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tripID: String
    let plan: TripPlanner.CatchUp

    private var store: TripStore { .shared }

    var body: some View {
        let trip = store.trips[tripID]?.trip
        let day = trip?.day ?? model.today
        let f = model.formats
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(plan.picks.isEmpty ? "Nothing else fits" : "Here’s what fits")
                        .font(Theme.display(28))
                        .foregroundStyle(Theme.ink)
                    Text(summary(day: day, endTitle: trip.map { f.time($0.day, Double($0.endMinute)) } ?? ""))
                        .foregroundStyle(Theme.ink2)

                    if !plan.plan.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(plan.plan, id: \.stop.id) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    if let mode = item.travelMode, item.travelMinutes > 0 {
                                        Label("\(TimeText.duration(item.travelMinutes)) \(mode == .walk ? "walk" : "drive")",
                                              systemImage: mode == .walk ? "figure.walk" : "car.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Theme.ink3)
                                    }
                                    HStack(spacing: 12) {
                                        Text(f.time(day, Double(item.start)))
                                            .font(.subheadline.weight(.bold).monospacedDigit())
                                            .foregroundStyle(item.lateBy > 0 ? Theme.bad : Theme.ink)
                                            .frame(width: 74, alignment: .trailing)
                                        Image(systemName: item.stop.kind.symbol)
                                            .foregroundStyle(item.stop.isFixed ? Theme.coreInk : Theme.softInk)
                                            .frame(width: 30, height: 30)
                                            .background(item.stop.isFixed ? Theme.core : Theme.soft, in: Circle())
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.stop.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                            Text(item.stop.isFixed ? "Set time" : "\(TimeText.duration(item.stop.stayMinutes)) · \(PriorityText.label(item.stop.priority))")
                                                .font(.caption)
                                                .foregroundStyle(Theme.ink3)
                                        }
                                    }
                                }
                            }
                        }
                        .card()
                    }

                    if plan.spare >= 10 && !plan.picks.isEmpty {
                        Label("\(TimeText.duration(plan.spare)) to spare", systemImage: "cup.and.saucer.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.good)
                    }

                    if !plan.skipped.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Not this time")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.ink)
                            ForEach(plan.skipped, id: \.stop.id) { skip in
                                Text(skipLine(skip))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.ink2)
                            }
                        }
                        .banner()
                    }

                    VStack(spacing: 10) {
                        Button("Use this plan", action: use)
                            .buttonStyle(.dtn(.primary, size: .big, wide: true))
                            .disabled(!store.canWrite(tripID))
                        Button("Keep my plan") { dismiss() }
                            .buttonStyle(.dtn(.quiet, wide: true))
                    }
                    Text("Stops that don’t fit before \(plan.next?.title ?? "the end of the day") go back on the wish list.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func summary(day: CalendarDay, endTitle: String) -> String {
        let f = model.formats
        let left = TimeText.duration(plan.available)
        guard let next = plan.next else {
            return "You have \(left) until \(endTitle), when you wanted to wrap up."
        }
        let at = f.time(day, Double(plan.deadline))
        if plan.lateForNext {
            return "Head to \(next.title) now. It starts at \(at)."
        }
        if plan.picks.isEmpty {
            return "You have \(left) before \(next.title) at \(at), and nothing on your list fits in that. Head there early, or take a break."
        }
        return "You have \(left) before \(next.title) at \(at). Go here, in this order:"
    }

    private func skipLine(_ skip: TripPlanner.CatchUp.Skipped) -> String {
        if skip.tooLong {
            return "\(skip.stop.title) takes about \(TimeText.duration(skip.needs)) with travel, and you have \(TimeText.duration(plan.available))."
        }
        return "\(skip.stop.title) fits on its own (\(TimeText.duration(skip.needs))), but not alongside the stops above."
    }

    private func use() {
        guard let planner = store.planner(for: tripID) else { return }
        let applied = planner.applying(plan)
        store.update(applied.trip)
        store.save(applied.stops)
        model.show("New plan from \(model.formats.time(applied.trip.day, Double(plan.now))).")
        dismiss()
    }
}
