import SwiftUI
import MutualKit

/// "Start from a ready-made deck": pick one of the built-in Indianapolis decks,
/// look through its cards, leave out what you don't want, and copy the rest
/// into a new deck in your group. The copy is an ordinary deck you can edit.
struct StarterSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Opens straight on one deck's preview (used by the screenshots).
    var initialDeckID: String?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(Starter.decks) { deck in
                        NavigationLink(value: deck.id) {
                            StarterDeckRow(deck: deck)
                        }
                    }
                } footer: {
                    Text("Places around Indianapolis, checked open in \(Starter.lastChecked). Photos come from each place’s own website.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Ready-made decks")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { id in
                if let deck = Starter.decks.first(where: { $0.id == id }) {
                    StarterPreview(deck: deck) { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if let initialDeckID, path.isEmpty { path = [initialDeckID] }
        }
    }
}

private struct StarterDeckRow: View {
    let deck: StarterDeck

    var body: some View {
        HStack(spacing: 12) {
            let photo = deck.cards.lazy.compactMap { StarterPhoto.image(named: $0.photoName) }.first
            CardThumb(title: deck.title, colorID: deck.id, photo: photo, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(deck.blurb).font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
                Text("\(deck.cards.count) cards").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// One starter deck's cards, with a filter by sub-category and a tap to leave a card out.
private struct StarterPreview: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let deck: StarterDeck
    let done: () -> Void

    /// The sub-categories to show. Empty means all of them.
    @State private var sections: Set<String> = []
    @State private var dropped: Set<String> = []

    private var shown: [StarterCard] {
        deck.cards.filter { sections.isEmpty || sections.contains($0.section) }
    }

    private var kept: [StarterCard] {
        shown.filter { !dropped.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                Text(deck.blurb).foregroundStyle(Theme.muted)
                if deck.sections.count > 1 {
                    FlowLayout(spacing: 8) {
                        chip("All", isOn: sections.isEmpty) { sections = [] }
                        ForEach(deck.sections, id: \.self) { section in
                            chip(section, isOn: sections.contains(section)) {
                                if sections.contains(section) { sections.remove(section) } else { sections.insert(section) }
                                if sections.count == deck.sections.count { sections = [] }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color.clear)

            Section {
                ForEach(shown) { card in
                    let isKept = !dropped.contains(card.id)
                    Button {
                        if isKept { dropped.insert(card.id) } else { dropped.remove(card.id) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            CardThumb(title: card.title, colorID: card.id, photo: StarterPhoto.image(named: card.photoName), size: 48)
                                .opacity(isKept ? 1 : 0.4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title).font(.body.weight(.semibold)).foregroundStyle(isKept ? Theme.ink : Theme.muted)
                                    .strikethrough(!isKept)
                                Text(card.facts).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                                Text(card.about).font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isKept ? Theme.accent : Theme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isKept ? .isSelected : [])
                    .accessibilityHint(isKept ? "Tap to leave this card out" : "Tap to add this card back")
                }
            } header: {
                Text("\(kept.count) card\(kept.count == 1 ? "" : "s") will be added")
                    .font(.subheadline.weight(.bold))
                    .textCase(nil)
            } footer: {
                Text("Tap a card to leave it out. The new deck is yours: edit, add or delete cards any time.")
            }

            Section {
                Button("Make this deck", action: make)
                    .buttonStyle(.mutual(wide: true))
                    .disabled(kept.isEmpty)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Theme.bg : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isOn ? Theme.ink : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Theme.ink : Theme.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func make() {
        let group = session.group(in: store) ?? store.ensureGroup()
        guard store.canWrite(group.id) else {
            session.show(Session.readOnlyMessage)
            return
        }
        guard let target = store.createDeck(in: group.id, title: deck.title, kind: deck.kind, blurb: deck.blurb) else { return }
        let added = store.addCards(kept.map(\.draft), to: target.id)
        session.currentGroupID = group.id
        session.show("Made “\(target.title)” with \(added) card\(added == 1 ? "" : "s")")
        done()
        session.openingTab[target.id] = .swipe
        session.path = [target.id]
    }
}
