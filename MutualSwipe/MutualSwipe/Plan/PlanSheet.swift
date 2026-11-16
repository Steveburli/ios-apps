import SwiftUI
import PhotosUI
import MapKit
import MutualKit

/// Makes or edits an itinerary card. A new plan starts from a pasted link or
/// text: Mutual pulls out the stops and times, finds each place on the map
/// and gets a photo from each place's own website. Then everything is shown
/// here to check and fix before it's saved.
struct PlanSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let deckID: String
    let cardID: String?

    private enum Step { case paste, edit }

    @State private var step: Step = .paste
    @State private var pasted = ""
    @State private var busy: String?
    @State private var notice: String?
    @State private var title = ""
    @State private var subtitle = ""
    @State private var details = ""
    @State private var link = ""
    @State private var area = ""
    @State private var tags: [String] = []
    @State private var stops: [Itinerary.Stop] = []
    @State private var photos: [String] = []
    @State private var photoLink = ""
    @State private var picked: [PhotosPickerItem] = []
    @State private var loaded = false

    private var plan: Itinerary {
        Itinerary(stops: stops, photos: photos, area: area)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && stops.contains { !$0.place.trimmingCharacters(in: .whitespaces).isEmpty || !$0.what.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if step == .paste {
                        pasteStep
                    } else {
                        editStep
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(cardID == nil ? "New plan" : "Edit plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if step == .edit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave || busy != nil)
                    }
                }
            }
            .overlay {
                if let busy {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(busy).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        }
                        .padding(22)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .interactiveDismissDisabled(step == .edit)
        .onAppear(perform: load)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPicked(items) }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let cardID, let card = store.cards[cardID] else { return }
        title = card.title
        subtitle = card.subtitle
        details = card.details
        link = card.link
        tags = card.tags
        let existing = card.plan ?? Itinerary()
        stops = existing.stops.isEmpty ? [Itinerary.Stop()] : existing.stops
        photos = existing.photos
        area = existing.area
        step = .edit
    }

    // MARK: Paste

    private var pasteStep: some View {
        VStack(spacing: 12) {
            Panel {
                Text("Plan a night out").font(Theme.display(20, weight: .bold))
                Text("Paste a link to a plan, or type it out, like “Drinks at 4 pm, movie at 6, dinner at 8”. Mutual pulls out the stops and times, puts them on a map and gets photos from each place’s own website. You check it all before it’s saved.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                TextField("Link or plan", text: $pasted, axis: .vertical)
                    .lineLimit(4...10)
                    .textInputAutocapitalization(.sentences)
                    .padding(12)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1.5))
                    .accessibilityLabel("Link or plan")
                HStack {
                    PasteButton(payloadType: String.self) { strings in
                        let text = strings.joined(separator: "\n")
                        Task { @MainActor in pasted = text }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleAndIcon)
                    Spacer()
                }
                Button {
                    Task { await build() }
                } label: {
                    Label("Build the card", systemImage: "wand.and.stars")
                }
                .buttonStyle(.mutual(wide: true))
                .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy != nil)
                Button("Start from scratch") {
                    stops = [Itinerary.Stop(), Itinerary.Stop()]
                    step = .edit
                }
                .buttonStyle(.mutual(.quiet, wide: true))
            }
            Text("Only the stops and times are copied from a link. Write the rest in your own words, and photos come from the places themselves or your phone.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func build() async {
        busy = "Reading the plan…"
        let built = await PlanBuilder.build(from: pasted) { busy = $0 }
        title = built.title
        link = built.link
        area = built.plan.area
        stops = built.plan.stops.isEmpty ? [Itinerary.Stop()] : built.plan.stops
        photos = built.plan.photos
        notice = built.notice
        let count = built.plan.stops.count
        subtitle = [ItineraryText.area(in: built.title), count > 0 ? "\(count) \(count == 1 ? "stop" : "stops")" : ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        busy = nil
        step = .edit
    }

    // MARK: Edit

    private var editStep: some View {
        VStack(spacing: 12) {
            if let notice {
                Text(notice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Panel {
                Text("The plan").font(Theme.display(18, weight: .bold))
                Field(label: "Title", text: $title, placeholder: "Dinner and a movie in Broad Ripple")
                Field(label: "Quick facts", text: $subtitle, placeholder: "Broad Ripple · $$ · 3 stops")
                Field(label: "About it", text: $details, placeholder: "Why it’s a good night, in your own words", axis: .vertical)
                Field(label: "Area", text: $area, placeholder: "Neighborhood or city, to find the places")
            }

            Panel {
                Text("Stops").font(Theme.display(18, weight: .bold))
                Text("In order. Times are optional.").font(.footnote).foregroundStyle(Theme.muted)
                ForEach($stops) { $stop in
                    let index = stops.firstIndex { $0.id == stop.id } ?? 0
                    StopEditor(stop: $stop, number: index + 1, count: stops.count, area: area,
                               near: nearCoordinate(before: index),
                               move: { move(stop.id, by: $0) },
                               remove: { stops.removeAll { $0.id == stop.id } })
                    Divider().overlay(Theme.line)
                }
                Button {
                    stops.append(Itinerary.Stop())
                } label: {
                    Label("Add a stop", systemImage: "plus")
                }
                .buttonStyle(.mutual(.quiet))
                .disabled(stops.count >= Itinerary.maxStops)
            }

            if stops.contains(where: \.hasLocation) {
                PlanMap(plan: plan, interactive: true, autoLocate: false)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
            }

            photoPanel

            Panel {
                Field(label: "Link (optional)", text: $link, placeholder: "https://", keyboard: .URL)
                Button {
                    Task { await save() }
                } label: {
                    Text(cardID == nil ? "Add the plan" : "Save changes")
                }
                .buttonStyle(.mutual(wide: true))
                .disabled(!canSave || busy != nil)
            }
        }
    }

    private var photoPanel: some View {
        Panel {
            Text("Photos").font(Theme.display(18, weight: .bold))
            Text("People swipe through these sideways on the card. The first is the cover.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.element) { index, ref in
                            PlanPhoto(ref: ref)
                                .frame(width: 96, height: 124)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photos.removeAll { $0 == ref }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(Color.white, Color.black.opacity(0.6))
                                    }
                                    .padding(4)
                                    .accessibilityLabel("Remove photo \(index + 1)")
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if index > 0 {
                                        Button {
                                            photos.swapAt(index, index - 1)
                                        } label: {
                                            Image(systemName: "arrow.left.circle.fill")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(Color.white, Color.black.opacity(0.6))
                                        }
                                        .padding(4)
                                        .accessibilityLabel("Move photo \(index + 1) earlier")
                                    }
                                }
                        }
                    }
                }
            }
            FlowLayout {
                PhotosPicker(selection: $picked, maxSelectionCount: max(1, Itinerary.maxPhotos - photos.count), matching: .images) {
                    Label("Add from your phone", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.mutual(.quiet))
                .disabled(photos.count >= Itinerary.maxPhotos)
                Button {
                    Task {
                        busy = "Getting photos from the places’ websites…"
                        let located = await PlaceFinder.locate(plan)
                        stops = located.stops
                        photos = await PlanBuilder.venuePhotos(for: located)
                        busy = nil
                    }
                } label: {
                    Label("From the places’ websites", systemImage: "globe")
                }
                .buttonStyle(.mutual(.quiet))
                .disabled(photos.count >= Itinerary.maxPhotos || stops.allSatisfy { $0.place.isEmpty })
            }
            HStack(alignment: .bottom, spacing: 10) {
                Field(label: "Photo link", text: $photoLink, placeholder: "https://…/photo.jpg", keyboard: .URL)
                Button("Add") {
                    if let ref = PhotoRef(photoLink), case .web = ref, !photos.contains(ref.string) {
                        photos.append(ref.string)
                        photoLink = ""
                    } else {
                        session.show("That isn’t an https photo link")
                    }
                }
                .buttonStyle(.mutual(.quiet))
                .disabled(photoLink.isEmpty || photos.count >= Itinerary.maxPhotos)
            }
        }
    }

    private func nearCoordinate(before index: Int) -> CLLocationCoordinate2D? {
        stops.prefix(index).reversed().first(where: \.hasLocation).map {
            CLLocationCoordinate2D(latitude: $0.latitude ?? 0, longitude: $0.longitude ?? 0)
        }
    }

    private func move(_ id: String, by offset: Int) {
        guard let from = stops.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard stops.indices.contains(to) else { return }
        stops.swapAt(from, to)
    }

    private func addPicked(_ items: [PhotosPickerItem]) async {
        busy = "Adding photos…"
        for item in items where photos.count < Itinerary.maxPhotos {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                  let ref = PlanPhotoStore.save(image) else { continue }
            photos.append(ref)
        }
        picked = []
        busy = nil
    }

    private func save() async {
        guard canSave, let deck = store.decks[deckID] else { return }
        guard store.canWrite(deck.groupID) else {
            session.show(Session.readOnlyMessage)
            return
        }
        busy = "Finding the places on the map…"
        var located = await PlaceFinder.locate(plan)
        located.stops.removeAll { $0.what.trimmingCharacters(in: .whitespaces).isEmpty && $0.place.trimmingCharacters(in: .whitespaces).isEmpty }
        busy = nil
        let draft = CardDraft(title: title, subtitle: subtitle, details: details, link: link, tags: tags, plan: located)
        if let cardID {
            store.updateCard(cardID, draft: draft)
            session.show("Plan saved")
        } else if store.addCards([draft], to: deckID) > 0 {
            session.show("Plan added")
        }
        dismiss()
    }
}

/// One stop's fields, with a button to find it on the map.
private struct StopEditor: View {
    @Binding var stop: Itinerary.Stop
    let number: Int
    let count: Int
    let area: String
    let near: CLLocationCoordinate2D?
    let move: (Int) -> Void
    let remove: () -> Void

    @State private var searching = false
    @State private var missed = false
    /// The place and address when the map search filled them in, so that
    /// fill-in doesn't count as an edit that loses the location.
    @State private var foundFor: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StopNumber(number: number)
                Text("Stop \(number)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                Spacer()
                Button { move(-1) } label: { Image(systemName: "arrow.up") }
                    .disabled(number == 1)
                    .accessibilityLabel("Move stop \(number) up")
                Button { move(1) } label: { Image(systemName: "arrow.down") }
                    .disabled(number == count)
                    .accessibilityLabel("Move stop \(number) down")
                Button(role: .destructive) { remove() } label: { Image(systemName: "trash") }
                    .disabled(count == 1)
                    .accessibilityLabel("Delete stop \(number)")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                Field(label: "Time", text: $stop.time, placeholder: "6:00 PM")
                    .frame(maxWidth: 120)
                Field(label: "What", text: $stop.what, placeholder: "Dinner")
            }
            Field(label: "Place", text: $stop.place, placeholder: "Name of the place")
            Field(label: "Address", text: $stop.address, placeholder: "Street or neighborhood")
            Field(label: "Note", text: $stop.note, placeholder: "What to order, what to book")
            HStack(spacing: 10) {
                Button {
                    Task { await find() }
                } label: {
                    Label(stop.hasLocation ? "Find again" : "Find on the map", systemImage: "mappin.and.ellipse")
                }
                .buttonStyle(.mutual(.quiet))
                .disabled(stop.place.trimmingCharacters(in: .whitespaces).isEmpty || searching)
                if searching {
                    ProgressView()
                } else if stop.hasLocation {
                    Label("On the map", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Vote.like.color)
                } else if missed {
                    Text("Not found. Add the street or city.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: stop.place) { _, _ in forgetLocation() }
        .onChange(of: stop.address) { _, _ in forgetLocation() }
    }

    private func forgetLocation() {
        guard !searching, foundFor != stop.place + "|" + stop.address else { return }
        stop.latitude = nil
        stop.longitude = nil
        missed = false
    }

    private func find() async {
        searching = true
        defer { searching = false }
        guard let found = await PlaceFinder.find(stop.searchText(area: area), near: near) else {
            missed = true
            return
        }
        missed = false
        stop.latitude = found.latitude
        stop.longitude = found.longitude
        if stop.address.isEmpty { stop.address = found.address }
        if stop.website.isEmpty { stop.website = found.website }
        foundFor = stop.place + "|" + stop.address
    }
}
