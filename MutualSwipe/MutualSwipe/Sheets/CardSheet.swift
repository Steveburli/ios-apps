import SwiftUI
import PhotosUI
import MutualKit

/// A card's details, its photos, your vote, and everyone else's once you've voted.
struct CardSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let cardID: String
    @State private var addingEvent = false
    @State private var confirmingRetire = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var addingPhotos = false
    @State private var viewing: PhotoViewer?

    private struct PhotoViewer: Identifiable {
        let id: String
    }

    var body: some View {
        NavigationStack {
            Group {
                if let card = store.cards[cardID], let deck = store.decks[card.deckID] {
                    content(card, deck: deck)
                } else {
                    ContentUnavailableView("This card was deleted", systemImage: "rectangle.badge.minus")
                }
            }
            .background(Theme.surface.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $addingEvent) {
            if let card = store.cards[cardID] {
                EventEditor(card: card) { addingEvent = false }
                    .ignoresSafeArea()
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPicked(items) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { add([image]) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { start in
            PhotoPager(photos: store.photos(of: cardID), startID: start.id)
        }
    }

    // MARK: Photos

    private func photoSection(_ card: Card, deck: Deck) -> some View {
        let added = store.photos(of: card.id)
        let room = CardPhotos.room(after: added.count)
        let canWrite = store.canWrite(deck.groupID)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                heading("Photos")
                Spacer()
                if !added.isEmpty {
                    Text("\(added.count) of \(CardPhotos.limit)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                }
            }
            if !added.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(added) { photo in
                            Button {
                                viewing = PhotoViewer(id: photo.id)
                            } label: {
                                PhotoTile(id: photo.id, size: 96)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(photo.addedBy.isEmpty ? "Photo" : "Photo added by \(photo.addedBy)")
                            .contextMenu {
                                if canWrite {
                                    Button("Remove photo", systemImage: "trash", role: .destructive) {
                                        store.removePhoto(photo.id)
                                        session.show("Photo removed")
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }
            if canWrite {
                if room > 0 {
                    Text(CardPhotos.tip)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    FlowLayout {
                        if let maps = CardPhotos.mapsURL(for: card) {
                            Link(destination: maps) {
                                Label("Find photos in Google Maps", systemImage: "map")
                            }
                            .buttonStyle(.mutual(.quiet))
                        }
                        PhotosPicker(selection: $photoItems, maxSelectionCount: room, matching: .images) {
                            Label(added.isEmpty ? "Add photos" : "Add more", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.mutual(.quiet))
                        .disabled(addingPhotos)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showCamera = true
                            } label: {
                                Label("Take a photo", systemImage: "camera")
                            }
                            .buttonStyle(.mutual(.quiet))
                            .disabled(addingPhotos)
                        }
                    }
                    if addingPhotos {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    Text("This card has \(CardPhotos.limit) photos, the most it holds. Press and hold one to remove it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                if !added.isEmpty && room > 0 {
                    Text("Press and hold a photo to remove it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func addPicked(_ items: [PhotosPickerItem]) async {
        addingPhotos = true
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        addingPhotos = false
        add(images)
    }

    private func add(_ images: [UIImage]) {
        guard let card = store.cards[cardID], !images.isEmpty else { return }
        let name = session.me(in: card.groupID, store: store).flatMap { store.players[$0]?.name }
        let added = store.addPhotos(images, to: cardID, by: name)
        if added == 0 {
            session.show("Couldn’t add that photo")
        } else if added < images.count {
            session.show("Added \(added). A card holds \(CardPhotos.limit) photos.")
        } else {
            session.show(added == 1 ? "Photo added" : "\(added) photos added")
        }
    }

    private func content(_ card: Card, deck: Deck) -> some View {
        let me = session.me(in: deck.groupID, store: store)
        let state = store.liveState(of: deck.id, me: me, vetting: !session.showsRound(deck))
        let mine = me.flatMap { state.vote(of: $0, on: card.id) }
        let others = state.participants.filter { $0 != me && state.vote(of: $0, on: card.id) != nil }
        let verdict = state.verdict(for: card)
        let round = session.showsRound(deck) ? deck.activeRound : nil
        let starter = Starter.match(card)
        let cover = store.coverImage(for: card)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deck.kind.label.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .opacity(0.85)
                    Text(card.title)
                        .font(Theme.display(30))
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle).font(.subheadline.weight(.semibold)).opacity(0.95)
                    }
                }
                .foregroundStyle(Color.white)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: cover != nil ? 200 : 0, alignment: .bottomLeading)
                .background {
                    ZStack {
                        Theme.cardColor(card.id)
                        if let photo = cover {
                            GeometryReader { box in
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: box.size.width, height: box.size.height)
                                    .clipped()
                            }
                            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        } else {
                            RadialGradient(colors: [Color.white.opacity(0.17), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                if mine != nil && state.participants.count > 1 && verdict != .pending {
                    Pill(text: verdict.label, tint: verdict.isMatch ? Theme.accent : Theme.ink,
                         background: verdict.isMatch ? Theme.accentSoft : Theme.sunk)
                }
                if !card.details.isEmpty {
                    Text(card.details)
                        .lineSpacing(3)
                        .foregroundStyle(Theme.ink)
                }
                if !card.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(card.tags, id: \.self) { Pill(text: $0) }
                    }
                }
                if let url = URL(string: card.link), !card.link.isEmpty {
                    Link(destination: url) {
                        Label("Open \(CardText.host(card.link))", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.mutual(.quiet))
                }
                when(card, canWrite: store.canWrite(deck.groupID))
                if starter?.website.isEmpty == false {
                    Text("From Mutual’s ready-made decks. Last checked \(Starter.lastChecked), so check hours before you go.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                photoSection(card, deck: deck)

                let isDecided = deck.decidedCards.contains(card.id)
                if isDecided || verdict.isMatch {
                    heading("Next step")
                    FlowLayout {
                        Button {
                            addingEvent = true
                        } label: {
                            Label("Add to calendar", systemImage: "calendar.badge.plus")
                        }
                        .buttonStyle(.mutual(isDecided ? .primary : .quiet))
                        ShareLink(item: EventInvite(card: card),
                                  preview: SharePreview(card.title, image: Image(systemName: "calendar"))) {
                            Label("Send invite", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.mutual(.quiet))
                        .accessibilityHint("Sends a calendar invite others can tap to add it to their own calendar.")
                        if store.canWrite(deck.groupID) {
                            Button {
                                let name = me.flatMap { store.players[$0]?.name }
                                store.setDecided(!isDecided, card: card.id, by: name)
                                if !isDecided { session.markDecisionSeen(deck) }
                                session.show(isDecided ? "No longer decided" : "Marked as decided for everyone")
                            } label: {
                                Label(isDecided ? "Not decided after all" : "Mark as decided",
                                      systemImage: isDecided ? "arrow.uturn.backward" : "checkmark.seal")
                            }
                            .buttonStyle(.mutual(isDecided ? .quiet : .primary))
                        }
                    }
                    Text(isDecided
                         ? "Decided. Add it to a shared calendar, or send the invite so others can add it to theirs."
                         : "Mark it decided and it moves to the top of Results for everyone.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                heading(round == nil ? "Your vote" : "Your vote this round")
                if let me {
                    HStack(spacing: 8) {
                        ForEach([Vote.never, .nope, .like, .love]) { vote in
                            Button {
                                guard store.canWrite(deck.groupID) else {
                                    session.show(Session.readOnlyMessage)
                                    return
                                }
                                store.setVote(vote, card: card.id, player: me, round: round)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: vote.symbol).foregroundStyle(vote.color)
                                    Text(vote.label(round: round != nil)).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                                }
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(mine == vote ? vote.soft : Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(mine == vote ? vote.color : Theme.line, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(vote.long(round: round != nil))
                            .accessibilityAddTraits(mine == vote ? .isSelected : [])
                        }
                    }
                } else {
                    Button("Choose your name to vote") { session.sheet = .player(deck.groupID) }
                        .buttonStyle(.mutual(.quiet))
                }

                heading("Everyone else")
                if others.isEmpty {
                    Text("No one else has voted on this yet.").font(.footnote).foregroundStyle(Theme.muted)
                } else if me != nil && mine == nil {
                    Text("\(others.count) \(others.count == 1 ? "person has" : "people have") voted. Cast yours to see how.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                } else {
                    VStack(spacing: 8) {
                        ForEach(others, id: \.self) { id in
                            if let vote = state.vote(of: id, on: card.id) {
                                HStack(spacing: 10) {
                                    PlayerDot(player: store.players[id])
                                    Text(store.players[id]?.name ?? "Someone").font(.body.weight(.semibold))
                                    Spacer()
                                    Label(vote.long(round: round != nil), systemImage: vote.symbol)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(vote.color)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 3)
                                        .background(vote.soft, in: Capsule())
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                if store.canWrite(deck.groupID) {
                    retireButton(card, me: me)
                        .padding(.top, 12)
                }
            }
            .padding(16)
        }
        .confirmationDialog("Never “\(card.title)”, for good?", isPresented: $confirmingRetire, titleVisibility: .visible) {
            Button("Never, for good", role: .destructive) {
                store.retire(card: card.id, by: me.flatMap { store.players[$0]?.name })
                session.show("“\(card.title)” is out for good")
                dismiss()
            }
        } message: {
            Text("It leaves this deck’s rounds and stacks for everyone, until someone brings it back from the Cards tab.")
        }
    }

    @ViewBuilder
    private func retireButton(_ card: Card, me: String?) -> some View {
        if card.isRetired {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(card.retiredBy.flatMap { $0.isEmpty ? nil : $0 } ?? "Someone") marked this “Never, for good”.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                Button("Bring it back") {
                    store.bringBack(card: card.id)
                    session.show("“\(card.title)” is back in the deck")
                }
                .buttonStyle(.mutual(.quiet))
            }
        } else {
            Button {
                confirmingRetire = true
            } label: {
                Label("Never, for good", systemImage: "nosign")
            }
            .buttonStyle(.mutual(.danger))
        }
    }

    /// The card's optional date and time, for events. Anyone who can edit
    /// the group can set, change or remove it.
    @ViewBuilder
    private func when(_ card: Card, canWrite: Bool) -> some View {
        if let time = card.startsAt {
            HStack(spacing: 8) {
                if canWrite {
                    DatePicker(selection: Binding(get: { time }, set: { store.setTime($0, card: card.id) })) {
                        Label("When", systemImage: "clock").foregroundStyle(Theme.ink)
                    }
                    Button {
                        store.setTime(nil, card: card.id)
                        session.show("Time removed")
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Remove the time")
                } else {
                    Label(time.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
        } else if canWrite {
            Button {
                store.setTime(CalendarPlan.placeholderStart(after: Date()), card: card.id)
            } label: {
                Label("Add a date and time", systemImage: "clock.badge.plus")
            }
            .buttonStyle(.mutual(.quiet))
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.footnote.weight(.bold))
            .tracking(1)
            .foregroundStyle(Theme.muted)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}
