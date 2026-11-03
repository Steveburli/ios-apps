import SwiftUI
import MapKit
import DoThisNowKit

/// Trip mode, the Day tab's third page: one day out planned stop by stop,
/// with travel times, fixed stops, a wish list and "We're off schedule".
struct TripView: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: TripSheet?
    @State private var finder = HereFinder()
    @State private var locating = false
    @State private var sharing = false

    private var store: TripStore { .shared }

    var body: some View {
        Group {
            if let entry = store.selected, let planner = store.planner(for: entry.trip.id) {
                page(entry, planner)
            } else {
                empty
            }
        }
        .sheet(item: $sheet) { sheet in
            TripSheetContent(sheet: sheet)
                .environment(model)
        }
        .onAppear {
            if let id = store.selected?.trip.id { store.fetchLegs(for: id) }
            if Screenshots.screen == "tripcatchup", let id = store.selected?.trip.id, let planner = store.planner(for: id) {
                sheet = .catchUp(id, planner.catchUp(now: 660, here: nil))
            }
        }
    }

    // MARK: No trip yet

    private var empty: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Plan a day out")
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.ink)
                Text("Add the things with set times, like a show, check-in or a dinner booking, and the places you’d like to fit around them. You’ll see when you’ll get to each one, walking or driving, and if you fall behind, one button works out what still fits.")
                    .foregroundStyle(Theme.ink2)
                Button("New trip") { sheet = .newTrip }
                    .buttonStyle(.dtn(.primary, size: .big, wide: true))
                Button("Try an example trip") { store.addExample(on: model.today) }
                    .buttonStyle(.dtn(wide: true))
            }
            .card()
            .padding(16)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: The trip

    private func page(_ entry: TripStore.TripEntry, _ planner: TripPlanner) -> some View {
        let trip = entry.trip
        let schedule = planner.schedule()
        let canWrite = !entry.readOnly
        let move: ((IndexSet, Int) -> Void)? = canWrite ? { source, destination in
            store.moveDay(trip.id, from: source, to: destination)
        } : nil
        return List {
            Section {
                header(entry, schedule)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            if schedule.items.contains(where: { $0.stop.coordinate != nil }) {
                Section {
                    TripMap(items: schedule.items)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }

            ForEach(schedule.warnings, id: \.fixedID) { warning in
                Section {
                    LateCard(warning: warning, planner: planner, canWrite: canWrite)
                }
            }

            Section {
                ForEach(schedule.items, id: \.stop.id) { item in
                    StopRow(item: item, day: trip.day, walkLimit: trip.walkLimit) {
                        store.toggleDone(item.stop.id)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { sheet = .editStop(item.stop.id) }
                    .swipeActions(edge: .trailing) {
                        if canWrite && !item.stop.isFixed {
                            Button("Wish list") { store.setOnDay(item.stop.id, false) }
                                .tint(Theme.block)
                        }
                    }
                }
                .onMove(perform: move)
                if canWrite {
                    Button { sheet = .newStop(trip.id, onDay: true) } label: {
                        Label("Add a stop", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
            } header: {
                Text("The day")
            } footer: {
                finishLine(trip, schedule)
            }

            Section {
                let wish = planner.wishList
                if wish.isEmpty {
                    Text("Places you’d like to get to if there’s time. “We’re off schedule” picks from here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink3)
                }
                ForEach(wish) { stop in
                    WishRow(stop: stop, canWrite: canWrite) { store.setOnDay(stop.id, true) }
                        .contentShape(Rectangle())
                        .onTapGesture { sheet = .editStop(stop.id) }
                        .swipeActions(edge: .trailing) {
                            if canWrite {
                                Button("Delete", role: .destructive) { store.deleteStop(stop.id) }
                            }
                        }
                }
                if canWrite {
                    Button { sheet = .newStop(trip.id, onDay: false) } label: {
                        Label("Add to the wish list", systemImage: "star.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
            } header: {
                Text("Wish list")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private func header(_ entry: TripStore.TripEntry, _ schedule: TripSchedule) -> some View {
        let trip = entry.trip
        let f = model.formats
        let isToday = trip.day == model.today
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Menu {
                    ForEach(store.sortedTrips, id: \.trip.id) { other in
                        Button {
                            store.selectedTripID = other.trip.id
                            store.fetchLegs(for: other.trip.id)
                        } label: {
                            Label("\(other.trip.name) · \(f.shortDate(other.trip.day))",
                                  systemImage: other.trip.id == trip.id ? "checkmark" : (other.isShared ? "person.2" : "map"))
                        }
                    }
                    Divider()
                    Button { sheet = .newTrip } label: { Label("New trip", systemImage: "plus") }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text(trip.name)
                                .font(Theme.display(26))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.ink3)
                        }
                        Text(isToday ? "Today · \(f.shortDate(trip.day))" : f.shortDate(trip.day))
                            .font(.footnote)
                            .foregroundStyle(Theme.ink3)
                    }
                }
                .accessibilityLabel("Trip: \(trip.name). Switch trips")
                Spacer()
                if entry.isOwned && !trip.isExample {
                    Button { share(trip.id) } label: {
                        Image(systemName: entry.isShared ? "person.2.fill" : "person.crop.circle.badge.plus")
                            .frame(width: 40, height: 40)
                    }
                    .disabled(sharing)
                    .accessibilityLabel(entry.isShared ? "Shared. Manage people" : "Share this trip")
                }
                Button { sheet = .editTrip(trip.id) } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 40, height: 40)
                }
                .accessibilityLabel("Trip settings")
            }
            if entry.isShared {
                Label(sharedLine(entry), systemImage: "person.2")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
            }
            if trip.isExample {
                Tag(text: "Example trip", tone: .example)
            }
            if !entry.readOnly && (isToday || Screenshots.isActive) {
                HStack(spacing: 10) {
                    if trip.arrivedMinute == nil {
                        Button("We’re here") { arrived(trip) }
                            .buttonStyle(.dtn(wide: true))
                    }
                    Button {
                        offSchedule(trip.id)
                    } label: {
                        if locating {
                            ProgressView()
                        } else {
                            Text("We’re off schedule")
                        }
                    }
                    .buttonStyle(.dtn(.primary, wide: true))
                    .disabled(locating)
                }
            }
        }
    }

    private func sharedLine(_ entry: TripStore.TripEntry) -> String {
        if !entry.isOwned { return entry.readOnly ? "Shared with you · view only" : "Shared with you" }
        return entry.participants.isEmpty ? "Shared · waiting for people to join" : "Shared with " + entry.participants.formatted()
    }

    private func finishLine(_ trip: Trip, _ schedule: TripSchedule) -> some View {
        let f = model.formats
        return VStack(alignment: .leading, spacing: 4) {
            if !schedule.items.isEmpty {
                Text("Starts \(f.time(trip.day, Double(schedule.start))) · done about \(f.time(trip.day, Double(schedule.finish)))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink2)
            }
            if schedule.overEnd > 0 {
                Text("That’s \(TimeText.duration(schedule.overEnd)) past \(f.time(trip.day, Double(trip.endMinute))), when you wanted to wrap up. Move something to the wish list to make room.")
                    .font(.footnote)
                    .foregroundStyle(Theme.bad)
            }
            Text("Touch and hold a stop to drag it. Times are estimates.")
                .font(.caption)
                .foregroundStyle(Theme.ink3)
        }
    }

    // MARK: Actions

    private func arrived(_ trip: Trip) {
        var trip = trip
        trip.arrivedMinute = Int(model.calendar.minuteOfDay(model.now))
        trip.resumeMinute = nil
        trip.resumeStopID = nil
        store.update(trip)
        model.show("Planning from now, \(model.formats.time(model.now)).")
    }

    private func offSchedule(_ tripID: String) {
        locating = true
        Task {
            let here = await finder.locate()
            locating = false
            guard let planner = store.planner(for: tripID) else { return }
            let now = Int(model.calendar.minuteOfDay(Date()))
            sheet = .catchUp(tripID, planner.catchUp(now: now, here: here.map(Coordinate.init)))
        }
    }

    private func share(_ tripID: String) {
        sharing = true
        Task {
            defer { sharing = false }
            do {
                let share = try await store.share(for: tripID)
                TripSharing.present(share: share, container: store.container, title: store.trips[tripID]?.trip.name ?? "Trip")
            } catch {
                model.show(error.localizedDescription)
            }
        }
    }
}

// MARK: - Rows

extension StopKind {
    var symbol: String {
        switch self {
        case .meal: return "fork.knife"
        case .sight: return "binoculars.fill"
        case .shop: return "bag.fill"
        case .show: return "theatermasks.fill"
        case .stay: return "bed.double.fill"
        case .other: return "mappin"
        }
    }
}

enum PriorityText {
    static func label(_ priority: Int) -> String {
        switch priority {
        case 3...: return "Must do"
        case 2: return "Want to"
        default: return "If there’s time"
        }
    }
}

private struct StopRow: View {
    @Environment(AppModel.self) private var model
    let item: ScheduledStop
    let day: CalendarDay
    let walkLimit: Int
    let toggle: () -> Void

    var body: some View {
        let stop = item.stop
        let f = model.formats
        VStack(alignment: .leading, spacing: 6) {
            if let mode = item.travelMode {
                Label("\(item.travelIsEstimate ? "About " : "")\(TimeText.duration(item.travelMinutes)) \(mode == .walk ? "walk" : "drive")",
                      systemImage: mode == .walk ? "figure.walk" : "car.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink3)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(stop.isFixed ? "at" : "about")
                        .font(.caption2)
                        .foregroundStyle(Theme.ink3)
                    Text(f.time(day, Double(item.start)))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(item.lateBy > 0 ? Theme.bad : Theme.ink)
                }
                .frame(width: 74, alignment: .trailing)
                Image(systemName: stop.kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(stop.isFixed ? Theme.coreInk : Theme.softInk)
                    .frame(width: 32, height: 32)
                    .background(stop.isFixed ? Theme.core : Theme.soft, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(stop.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(stop.done ? Theme.ink3 : Theme.ink)
                        .strikethrough(stop.done)
                    Text([TimeText.duration(stop.stayMinutes) + " there", stop.address].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                    FlowLayout(spacing: 6) {
                        if stop.isFixed { Tag(text: "Set time") }
                        if item.lateBy > 0 { Tag(text: "\(TimeText.duration(item.lateBy)) late", tone: .bad) }
                        if item.wait >= 10 { Tag(text: "\(TimeText.duration(item.wait)) to spare") }
                    }
                }
                Spacer(minLength: 0)
                Button(action: toggle) {
                    Image(systemName: stop.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(stop.done ? Theme.good : Theme.ink3)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(stop.done ? "Done. Mark not done" : "Mark done")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct WishRow: View {
    let stop: TripStop
    let canWrite: Bool
    let add: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stop.kind.symbol)
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
                .frame(width: 32, height: 32)
                .background(Theme.surface2, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    Tag(text: PriorityText.label(stop.priority), tone: stop.priority >= StopPriority.top ? .hot : .plain)
                    Text(TimeText.duration(stop.stayMinutes))
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 0)
            if canWrite {
                Button(action: add) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(stop.title) to the day")
            }
        }
    }
}

private struct LateCard: View {
    @Environment(AppModel.self) private var model
    let warning: LateWarning
    let planner: TripPlanner
    let canWrite: Bool

    var body: some View {
        let fixed = planner.stops.first { $0.id == warning.fixedID }
        VStack(alignment: .leading, spacing: 10) {
            Label("You’d be \(TimeText.duration(warning.lateBy)) late for \(fixed?.title ?? "a set time")",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.bad)
            if warning.fixes.isEmpty {
                Text("No single change fixes it. Move a stop or two to the wish list, or shorten the time at one.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
            } else if canWrite {
                ForEach(Array(warning.fixes.prefix(4).enumerated()), id: \.offset) { _, fix in
                    Button(label(fix, fixedTitle: fixed?.title ?? "it")) {
                        TripStore.shared.save(planner.applying(fix))
                        model.show("Done. You’ll make \(fixed?.title ?? "it") on time.")
                    }
                    .buttonStyle(.dtn(size: .small))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func label(_ fix: ScheduleFix, fixedTitle: String) -> String {
        let title = planner.stops.first { $0.id == fix.stopID }?.title ?? "that stop"
        switch fix {
        case .drop: return "Move \(title) to the wish list"
        case .moveAfter: return "Do \(title) after \(fixedTitle)"
        }
    }
}

/// The day's stops on a map, joined in order.
private struct TripMap: View {
    let items: [ScheduledStop]

    var body: some View {
        let placed = items.filter { $0.stop.coordinate != nil }
        Map(initialPosition: .automatic) {
            ForEach(Array(placed.enumerated()), id: \.element.stop.id) { index, item in
                Marker("\(index + 1). \(item.stop.title)", systemImage: item.stop.kind.symbol,
                       coordinate: item.stop.coordinate!.location)
                    .tint(item.stop.isFixed ? Theme.core : Theme.accent)
            }
            if placed.count > 1 {
                MapPolyline(coordinates: placed.map { $0.stop.coordinate!.location })
                    .stroke(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 6]))
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .id(placed.map { $0.stop.id }.joined())
        .accessibilityLabel("Map of the day’s stops")
    }
}
