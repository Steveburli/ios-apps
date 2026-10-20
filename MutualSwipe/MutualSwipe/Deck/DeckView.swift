import SwiftUI
import MutualKit

/// One deck: Swipe, Results and Cards.
struct DeckView: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let deckID: String
    @State private var tab: Session.DeckTab = .swipe

    var body: some View {
        if let deck = store.decks[deckID] {
            let state = store.state(of: deck.id, me: session.me(in: deck.groupID, store: store))
            VStack(spacing: 0) {
                Picker("Deck view", selection: $tab) {
                    Text("Swipe").tag(Session.DeckTab.swipe)
                    Text(state.matchCount > 0 ? "Results (\(state.matchCount))" : "Results").tag(Session.DeckTab.results)
                    Text(state.cards.isEmpty ? "Cards" : "Cards (\(state.cards.count))").tag(Session.DeckTab.cards)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)

                switch tab {
                case .swipe:
                    SwipeTab(deck: deck, state: state, showTab: { tab = $0 })
                case .results:
                    ResultsTab(deck: deck, state: state, showTab: { tab = $0 })
                case .cards:
                    CardsTab(deck: deck, state: state)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(deck.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    WhoButton(groupID: deck.groupID)
                }
            }
            .onAppear {
                if let opening = session.openingTab.removeValue(forKey: deckID) { tab = opening }
                if session.me(in: deck.groupID, store: store) == nil && !session.pickerShown {
                    session.pickerShown = true
                    session.sheet = .player(deck.groupID)
                }
            }
        } else {
            ContentUnavailableView("This deck was deleted", systemImage: "rectangle.stack.badge.minus",
                                   description: Text("Someone in the group deleted it."))
        }
    }
}
