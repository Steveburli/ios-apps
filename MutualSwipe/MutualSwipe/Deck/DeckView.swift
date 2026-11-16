import SwiftUI
import MutualKit

/// One deck: Swipe, Results, Overlap and Cards. While a round is running, Swipe and
/// Results show the round; the bar on top switches back to vetting.
struct DeckView: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let deckID: String
    @State private var tab: Session.DeckTab = .swipe

    var body: some View {
        if let deck = store.decks[deckID] {
            let me = session.me(in: deck.groupID, store: store)
            let vetting = store.state(of: deck.id, me: me)
            let state = store.liveState(of: deck.id, me: me, vetting: !session.showsRound(deck))
            VStack(spacing: 0) {
                Picker("Deck view", selection: $tab) {
                    Text("Swipe").tag(Session.DeckTab.swipe)
                    Text(state.matchCount > 0 ? "Results (\(state.matchCount))" : "Results").tag(Session.DeckTab.results)
                    Text("Overlap").tag(Session.DeckTab.overlap)
                    Text(vetting.cards.isEmpty ? "Cards" : "Cards (\(vetting.cards.count))").tag(Session.DeckTab.cards)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 10)

                if !deck.formQuestions.isEmpty && tab != .cards {
                    QuestionsBar(deck: deck, me: me)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                if !vetting.cards.isEmpty && tab != .cards {
                    RoundBar(deck: deck, me: me)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                switch tab {
                case .swipe:
                    SwipeTab(deck: deck, state: state, showTab: { tab = $0 })
                case .results:
                    ResultsTab(deck: deck, state: state, showTab: { tab = $0 })
                case .overlap:
                    OverlapTab(deck: deck, state: state)
                case .cards:
                    CardsTab(deck: deck, state: vetting)
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
                openQuestionsIfNeeded()
            }
            // After picking a name, or when the questions arrive from iCloud.
            .onChange(of: session.sheet?.id) { _, _ in openQuestionsIfNeeded() }
            .onChange(of: deck.formQuestions.count) { _, _ in openQuestionsIfNeeded() }
        } else {
            ContentUnavailableView("This deck was deleted", systemImage: "rectangle.stack.badge.minus",
                                   description: Text("Someone in the group deleted it."))
        }
    }

    /// A deck with questions shows them first: once per launch, before
    /// swiping, until this person has confirmed their answers.
    private func openQuestionsIfNeeded() {
        guard session.sheet == nil, session.path.last == deckID, let deck = store.decks[deckID],
              store.canWrite(deck.groupID),
              let me = session.me(in: deck.groupID, store: store),
              store.needsAnswers(deck: deckID, player: me) else { return }
        let key = deckID + "~" + me
        guard !session.formShown.contains(key) else { return }
        session.formShown.insert(key)
        tab = .swipe
        session.sheet = .answer(deckID, me)
    }
}

/// Above the stack: the round's question, or how far vetting has got.
private struct RoundBar: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let deck: Deck
    let me: String?
    @State private var confirm: Confirm?

    private enum Confirm: Identifiable {
        case newRound, end
        var id: Self { self }
    }

    var body: some View {
        HStack(spacing: 12) {
            if session.showsRound(deck) {
                round
            } else {
                vetting
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(session.showsRound(deck) ? Theme.accentSoft : Theme.surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        .confirmationDialog(confirm == .end ? "End this round?" : "Start a new round?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { item in
            switch item {
            case .newRound:
                Button("Start a new round", role: .destructive) {
                    store.startRound(deck: deck.id, question: deck.roundQuestion ?? Rounds.defaultQuestion)
                    session.show("New round started")
                }
            case .end:
                Button("End round", role: .destructive) {
                    store.endRound(deck: deck.id)
                    session.show("Round ended. Its winner is saved in Results.")
                }
            }
        } message: { item in
            switch item {
            case .newRound: Text("This clears everyone’s round votes. Vetting votes stay.")
            case .end: Text("Its winner is saved, and the deck goes back to vetting.")
            }
        }
    }

    @ViewBuilder
    private var round: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("ROUND").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(Theme.accent)
            Text(deck.roundQuestion ?? Rounds.defaultQuestion)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
        }
        Spacer(minLength: 6)
        Menu {
            Button {
                session.vettingShown.insert(deck.id)
            } label: {
                Label("Show vetting", systemImage: "checklist")
            }
            if store.canWrite(deck.groupID) {
                Button {
                    confirm = .newRound
                } label: {
                    Label("Start a new round", systemImage: "arrow.clockwise")
                }
                Button {
                    session.sheet = .startRound(deck.id)
                } label: {
                    Label("Change the question…", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    confirm = .end
                } label: {
                    Label("End round", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
        }
        .accessibilityLabel("Round options")
    }

    @ViewBuilder
    private var vetting: some View {
        let progress = store.vetting(of: deck.id)
        let names = progress.vetted.compactMap { store.players[$0]?.name }
        VStack(alignment: .leading, spacing: 1) {
            Text("VETTING · \(Vetting.percent(progress.group)) DONE")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            Group {
                if let me, let mine = progress.share[me] {
                    Text("You: \(Vetting.percent(mine))") + Text(names.isEmpty ? "" : " · Vetted: \(names.joined(separator: ", "))")
                } else {
                    Text(names.isEmpty ? "Not vetted yet" : "Vetted: \(names.joined(separator: ", "))")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        Spacer(minLength: 6)
        if deck.activeRound != nil {
            Button("Back to round") { session.vettingShown.remove(deck.id) }
                .buttonStyle(.mutual())
                .controlSize(.small)
        } else if store.canWrite(deck.groupID) {
            Button("Start a round") { session.sheet = .startRound(deck.id) }
                .buttonStyle(.mutual())
                .controlSize(.small)
        }
    }
}
