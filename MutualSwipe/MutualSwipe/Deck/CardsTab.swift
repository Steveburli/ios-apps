import SwiftUI
import MutualKit

/// Adding cards, the list of cards, and the deck's settings.
struct CardsTab: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let deck: Deck
    let state: DeckState

    @State private var title = ""
    @State private var subtitle = ""
    @State private var details = ""
    @State private var link = ""
    @State private var tags = ""
    @State private var bulk = ""
    @State private var deckTitle = ""
    @State private var deckBlurb = ""
    @State private var loaded = false
    @State private var confirm: Confirm?
    @FocusState private var titleFocused: Bool

    private enum Confirm: Identifiable {
        case card(Card), clearMine, deleteDeck
        var id: String {
            switch self {
            case .card(let card): return "card-" + card.id
            case .clearMine: return "clear"
            case .deleteDeck: return "deck"
            }
        }
    }

    private var canWrite: Bool { store.canWrite(deck.groupID) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !canWrite {
                    Text(Session.readOnlyMessage)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    addCard
                    pasteList
                }
                cardList
                if canWrite {
                    settings
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if !loaded {
                deckTitle = deck.title
                deckBlurb = deck.blurb
                loaded = true
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { item in
            switch item {
            case .card(let card):
                Button("Delete card", role: .destructive) {
                    store.deleteCard(card.id)
                    session.show("Card deleted")
                }
            case .clearMine:
                Button("Clear my swipes", role: .destructive) { clearMine() }
            case .deleteDeck:
                Button("Delete deck", role: .destructive) { deleteDeck() }
            }
        }
    }

    private var confirmTitle: String {
        switch confirm {
        case .card(let card): return "Delete “\(card.title)”?"
        case .clearMine: return "Clear your swipes for this deck?"
        case .deleteDeck: return "Delete “\(deck.title)” for everyone?"
        case nil: return ""
        }
    }

    private var addCard: some View {
        Panel {
            Text("Add a card").font(Theme.display(18, weight: .bold))
            Field(label: "Title", text: $title, placeholder: deck.kind.example)
                .focused($titleFocused)
            Field(label: "Quick facts", text: $subtitle, placeholder: deck.kind.hint)
            Field(label: "Details", text: $details, placeholder: "What it is and why it’s worth a swipe", axis: .vertical)
            HStack(spacing: 10) {
                Field(label: "Link", text: $link, placeholder: "https://", keyboard: .URL)
                Field(label: "Tags", text: $tags, placeholder: "cozy, quick")
            }
            Button("Add card") {
                guard let draft = CardText.clean(title: title, subtitle: subtitle, details: details, link: link, tags: tags) else {
                    titleFocused = true
                    return
                }
                if store.addCards([draft], to: deck.id) > 0 {
                    title = ""; subtitle = ""; details = ""; link = ""; tags = ""
                    session.show("Card added")
                    titleFocused = true
                }
            }
            .buttonStyle(.mutual())
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var pasteList: some View {
        Panel {
            Text("Paste a list").font(Theme.display(18, weight: .bold))
            Text("One card per line. Add facts and details after a bar: Title | quick facts | details")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            TextField("\(deck.kind.example) | \(deck.kind.hint)", text: $bulk, axis: .vertical)
                .lineLimit(5...12)
                .padding(12)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1.5))
                .accessibilityLabel("Cards to add, one per line")
            Button("Add all") {
                let drafts = CardText.parseList(bulk)
                let added = store.addCards(drafts, to: deck.id)
                if added > 0 {
                    bulk = ""
                    session.show("Added \(added) card\(added == 1 ? "" : "s")")
                }
            }
            .buttonStyle(.mutual(.quiet))
            .disabled(bulk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var cardList: some View {
        Panel {
            HStack(alignment: .firstTextBaseline) {
                Text("In this deck").font(Theme.display(18, weight: .bold))
                Text("\(state.cards.count)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.muted)
            }
            if state.cards.isEmpty {
                Text("No cards yet.").foregroundStyle(Theme.muted)
            }
            ForEach(state.cards) { card in
                HStack(spacing: 10) {
                    Text(CardText.initial(card.title))
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.cardColor(card.id), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                    Button {
                        session.sheet = .card(card.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.title).font(.body.weight(.semibold)).lineLimit(1).foregroundStyle(Theme.ink)
                            if !card.subtitle.isEmpty {
                                Text(card.subtitle).font(.footnote).lineLimit(1).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    if canWrite {
                        Button {
                            confirm = .card(card)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Theme.muted)
                                .frame(width: 38, height: 38)
                        }
                        .accessibilityLabel("Delete \(card.title)")
                    }
                }
                .padding(.vertical, 4)
                Divider().overlay(Theme.line)
            }
        }
    }

    private var settings: some View {
        Panel {
            Text("Deck settings").font(Theme.display(18, weight: .bold))
            Field(label: "Name", text: $deckTitle)
            Field(label: "Note", text: $deckBlurb, placeholder: "Budget, timing, anything to keep in mind")
            Button("Save") {
                store.updateDeck(deck.id, title: deckTitle, blurb: deckBlurb)
                session.show("Saved")
            }
            .buttonStyle(.mutual(.quiet))
            .disabled(deckTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            Divider().overlay(Theme.line)
            FlowLayout {
                if session.me(in: deck.groupID, store: store) != nil {
                    Button("Clear my swipes") { confirm = .clearMine }
                        .buttonStyle(.mutual(.quiet))
                }
                Button("Delete deck") { confirm = .deleteDeck }
                    .buttonStyle(.mutual(.danger))
            }
        }
    }

    private func clearMine() {
        guard let me = session.me(in: deck.groupID, store: store) else { return }
        store.clearVotes(deck: deck.id, player: me)
        session.clearUndo(deck: deck.id, player: me)
        session.show("Your swipes for this deck are cleared")
    }

    private func deleteDeck() {
        store.deleteDeck(deck.id)
        session.path.removeAll { $0 == deck.id }
        session.show("Deck deleted")
    }
}
