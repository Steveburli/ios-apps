import SwiftUI
import MapKit
import DoThisNowKit

/// Places and the rules that start and stop Track timers by them, plus what
/// the rules did lately, with Undo.
struct PlacesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Set when opened from an activity, so a new rule starts with it.
    var activityID: String?
    var embedded = false

    var body: some View {
        if embedded {
            list
        } else {
            NavigationStack {
                list
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
            }
        }
    }

    private var list: some View {
        let timers = model.state.placeTimers
        let watcher = PlaceWatcher.shared
        let rules = timers.rules.filter { activityID == nil || $0.activityID == activityID }
        return List {
            if !timers.rules.isEmpty && !watcher.isAlways {
                Section {
                    LocationWarning()
                }
            }

            Section {
                ForEach(rules) { rule in
                    RuleRow(rule: rule)
                }
                .onDelete { offsets in
                    for index in offsets { model.deletePlaceRule(rules[index].id) }
                }
                NavigationLink {
                    RuleForm(activityID: activityID)
                } label: {
                    Label("Add a rule", systemImage: "plus")
                }
                .disabled(model.state.activities.isEmpty)
            } header: {
                Text("Rules")
            } footer: {
                Text(model.state.activities.isEmpty
                     ? "Add something to time on the Track tab first."
                     : "For example: start Gym when I leave Home, and stop Gym when I leave the gym. A rule starts or stops the timer on its own and sends a quiet notification with Undo. If a rule started a timer and it’s still going an hour later, you’ll be asked whether to stop it.")
            }

            Section {
                ForEach(timers.places) { place in
                    NavigationLink {
                        PlaceForm(place: place)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).foregroundStyle(Theme.ink)
                            Text([place.address, "\(Int(place.radius)) m around it"].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.ink3)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { model.deleteWatchedPlace(timers.places[index].id) }
                }
                NavigationLink {
                    PlaceForm(place: nil)
                } label: {
                    Label("Add a place", systemImage: "mappin.and.ellipse")
                }
            } header: {
                Text("Places")
            } footer: {
                Text("iPhones check places loosely to save battery, so a rule can fire a few minutes early or late. Fix a time on the Track tab by tapping it.")
            }

            let recent = Array(timers.history.suffix(20).reversed())
            if !recent.isEmpty && activityID == nil {
                Section("Lately") {
                    ForEach(recent) { firing in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(firing.summary)
                                    .foregroundStyle(firing.undone ? Theme.ink3 : Theme.ink)
                                    .strikethrough(firing.undone)
                                Text(model.formats.shortDate(firing.at) + ", " + model.formats.time(firing.at)
                                     + (firing.undone ? " · undone" : ""))
                                    .font(.caption)
                                    .foregroundStyle(Theme.ink3)
                            }
                            Spacer()
                            if model.state.canUndo(firing) {
                                Button("Undo") { model.undoPlaceFiring(firing.id) }
                                    .buttonStyle(.dtn(size: .small))
                            }
                        }
                    }
                }
            }
        }
        .tint(Theme.accent)
        .navigationTitle("Start and stop by place")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Says when location isn't set to Always, and how to fix it.
struct LocationWarning: View {
    var body: some View {
        let watcher = PlaceWatcher.shared
        VStack(alignment: .leading, spacing: 8) {
            Label("Place rules need location set to Always", systemImage: "location.slash")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(watcher.isOff
                 ? "Location is off for Do This Now, so rules can’t fire. In Settings, tap Location and choose Always."
                 : "Right now the iPhone only lets Do This Now see where you are while it’s open, so rules won’t fire with the app closed. Choose Always.")
                .font(.footnote)
                .foregroundStyle(Theme.ink2)
            Button(watcher.isOff ? "Open Settings" : "Allow Always") { watcher.requestAlways() }
                .buttonStyle(.dtn(.primary, size: .small))
        }
        .padding(.vertical, 4)
    }
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let rule: PlaceRule

    var body: some View {
        let name = model.state.activity(rule.activityID)?.name ?? "Deleted"
        let place = model.state.placeTimers.place(rule.placeID)?.name ?? "a deleted place"
        Toggle(isOn: Binding(get: { rule.on }, set: { on in
            var edited = rule
            edited.on = on
            model.save(edited)
        })) {
            Text("\(rule.action == .start ? "Start" : "Stop") **\(name)** when I \(rule.crossing.verb) **\(place)**")
                .foregroundStyle(Theme.ink)
        }
    }
}

/// "Start [Gym] when I [leave] [Home]".
private struct RuleForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var activityID: String?
    @State private var activity = ""
    @State private var action = PlaceRule.Action.start
    @State private var crossing = PlaceCrossing.leave
    @State private var placeID = ""
    @State private var loaded = false

    var body: some View {
        let places = model.state.placeTimers.places
        Form {
            Section {
                Picker("Timer", selection: $activity) {
                    ForEach(model.state.activities) { Text($0.name).tag($0.id) }
                }
                Picker("Do", selection: $action) {
                    Text("Start it").tag(PlaceRule.Action.start)
                    Text("Stop it").tag(PlaceRule.Action.stop)
                }
                .pickerStyle(.segmented)
                Picker("When I", selection: $crossing) {
                    Text("Leave").tag(PlaceCrossing.leave)
                    Text("Arrive at").tag(PlaceCrossing.arrive)
                }
                .pickerStyle(.segmented)
                if places.isEmpty {
                    NavigationLink("Add a place first") { PlaceForm(place: nil) }
                } else {
                    Picker("Place", selection: $placeID) {
                        ForEach(places) { Text($0.name).tag($0.id) }
                    }
                }
            } footer: {
                if let name = model.state.activity(activity)?.name, let place = places.first(where: { $0.id == placeID }) {
                    Text("\(action == .start ? "Start" : "Stop") \(name) when I \(crossing.verb) \(place.name).")
                }
            }
        }
        .tint(Theme.accent)
        .navigationTitle("New rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.save(PlaceRule(activityID: activity, action: action, crossing: crossing, placeID: placeID))
                    dismiss()
                }
                .fontWeight(.bold)
                .disabled(model.state.activity(activity) == nil || !places.contains { $0.id == placeID })
            }
        }
        .onAppear {
            if !loaded {
                loaded = true
                activity = activityID ?? model.state.activities.first?.id ?? ""
            }
            // Picks the first place, including one just added from here.
            if !places.contains(where: { $0.id == placeID }) {
                placeID = places.last?.id ?? ""
            }
        }
    }
}

/// A place by search or where you are now, with a name and a size.
private struct PlaceForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let place: WatchedPlace?
    @State private var name = ""
    @State private var address = ""
    @State private var coordinate: Coordinate?
    @State private var radius = WatchedPlace.defaultRadius
    @State private var search = PlaceSearch()
    @State private var finder = HereFinder()
    @State private var finding = false
    @State private var problem: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("Name, like Home or Gym", text: $name)
                    .font(.body.weight(.semibold))
                    .textInputAutocapitalization(.words)
            }
            Section {
                if let coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate.location, latitudinalMeters: radius * 5,
                                                                    longitudinalMeters: radius * 5))) {
                        MapCircle(center: coordinate.location, radius: radius)
                            .foregroundStyle(Theme.accent.opacity(0.25))
                            .stroke(Theme.accent, lineWidth: 2)
                    }
                    .id("\(coordinate.key)-\(radius)")
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
                    if !address.isEmpty {
                        Text(address).font(.footnote).foregroundStyle(Theme.ink2)
                    }
                }
                Button {
                    useHere()
                } label: {
                    Label("Use where I am now", systemImage: "location.fill")
                }
                .disabled(finding)
                TextField("Or search an address or place", text: $search.query)
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
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(Theme.ink2)
                }
            } header: {
                Text("Where")
            }
            Section {
                ChoiceChips(options: WatchedPlace.radiusChoices.map { ($0, "\(Int($0)) m") }, selection: $radius)
            } header: {
                Text("How close counts as there")
            } footer: {
                Text("About 150 m (a city block) works for most places. Go bigger for a large building or parking lot, or if rules fire late.")
            }
        }
        .tint(Theme.accent)
        .navigationTitle(place == nil ? "New place" : "Edit place")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .fontWeight(.bold)
                    .disabled(coordinate == nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let place {
                name = place.name
                address = place.address
                coordinate = place.coordinate
                radius = place.radius
            }
        }
    }

    private func useHere() {
        finding = true
        problem = nil
        Task {
            let here = await finder.locate()
            finding = false
            if let here {
                coordinate = Coordinate(here)
                address = "Where you were when you added it"
            } else {
                problem = "Couldn’t find where you are. Check that location is on for Do This Now, or search instead."
            }
        }
    }

    private func pick(_ result: MKLocalSearchCompletion) {
        finding = true
        Task {
            if let found = await search.resolve(result) {
                coordinate = found.coordinate
                address = found.address
                if name.isEmpty { name = found.name }
                search.query = ""
            }
            finding = false
        }
    }

    private func save() {
        guard let coordinate else { return }
        var edited = place ?? WatchedPlace(name: "", coordinate: coordinate)
        edited.name = name.trimmingCharacters(in: .whitespaces)
        edited.address = address
        edited.coordinate = coordinate
        edited.radius = radius
        model.save(edited)
        dismiss()
    }
}
