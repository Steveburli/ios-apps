import SwiftUI
import MutualKit

/// What everyone agrees on, from super matches down to trash.
struct ResultsTab: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let deck: Deck
    let state: DeckState
    let showTab: (Session.DeckTab) -> Void
    @State private var openTiers: Set<Verdict> = []

    private var inRound: Bool { session.showsRound(deck) }

    var body: some View {
        let me = session.me(in: deck.groupID, store: store)
        let active = state.activeParticipants
        let n = state.participants.count
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !active.isEmpty {
                    FlowLayout {
                        ForEach(state.participants, id: \.self) { id in
                            HStack(spacing: 7) {
                                PlayerDot(player: store.players[id])
                                Text((store.players[id]?.name ?? "Someone") + (id == me ? " (you)" : ""))
                                    .font(.subheadline.weight(.semibold))
                                Text("\(state.progress[id] ?? 0)/\(state.cards.count)")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.leading, 3)
                            .padding(.trailing, 12)
                            .padding(.vertical, 3)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.line))
                        }
                    }
                }

                if state.cards.isEmpty {
                    Note("This deck has no cards yet.")
                } else if active.isEmpty {
                    Note("Nothing to compare yet. Swipe through the deck, then check back here.")
                } else if active.count < 2 {
                    Note("Only \(active[0] == me ? "you have" : "\(store.players[active[0]]?.name ?? "someone") has") swiped so far. Results firm up once someone else joins in.")
                }

                waiting(me: me, hasActive: !active.isEmpty)

                decisionBanner(me: me)
                nextInChain
                decided
                spinBar

                ForEach(Verdict.shown, id: \.self) { verdict in
                    let cards = state.cards(verdict).filter { !deck.decidedCards.contains($0.id) }
                    if !cards.isEmpty {
                        tier(verdict, cards: cards, people: n)
                    }
                }

                shareResults

                history
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    /// "Alex marked Sunset picnic as decided", until this phone dismisses it.
    @ViewBuilder
    private func decisionBanner(me: String?) -> some View {
        let myName = me.flatMap { store.players[$0]?.name }
        if session.hasNewDecision(deck, myName: myName), let last = deck.decidedCards.last.flatMap({ store.cards[$0] }) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Vote.like.color)
                Text("\(deck.decidedBy ?? "Someone") marked “\(last.title)” as decided.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                Button {
                    session.markDecisionSeen(deck)
                } label: {
                    Image(systemName: "xmark").foregroundStyle(Theme.muted).frame(width: 32, height: 32)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Vote.like.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private var decided: some View {
        let cards = deck.decidedCards.compactMap { store.cards[$0] }
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Vote.like.color)
                        .frame(width: 30, height: 30)
                        .background(Vote.like.soft, in: Circle())
                    Text("Decided").font(Theme.display(20, weight: .bold)).foregroundStyle(Theme.ink)
                }
                .accessibilityAddTraits(.isHeader)
                Text("Settled. Open one to add it to your calendar.").font(.footnote).foregroundStyle(Theme.muted)
                ForEach(cards) { card in
                    ResultRow(card: card, state: state, round: inRound)
                }
            }
            .padding(.top, 6)
        }
    }

    /// In a chained round, once there's a winner: go on to the next deck,
    /// narrowed to what won here.
    @ViewBuilder
    private var nextInChain: some View {
        if inRound, let nextID = deck.roundChain?.first(where: { store.decks[$0] != nil }), let next = store.decks[nextID],
           let winner = Rounds.winner(of: state, decided: deck.decidedCards, spin: deck.spinCardID) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Winner: \(winner.title)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("Next, pick from \(next.title), narrowed to “\(winner.title)”.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 6)
                if store.canWrite(deck.groupID) {
                    Button("Next") {
                        guard let id = store.startNextInChain(from: deck.id, winner: winner.id) else { return }
                        session.vettingShown.remove(id)
                        session.path.append(id)
                    }
                    .buttonStyle(.mutual())
                }
            }
            .padding(14)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        }
    }

    /// Sends the results as a little CSV (title,result), for pasting into
    /// another app such as Burlison's Pantry.
    @ViewBuilder
    private var shareResults: some View {
        if ResultsExport.hasResults(state) {
            ShareLink(item: ResultsExport.csv(state),
                      subject: Text("(deck.title) results"),
                      preview: SharePreview("(deck.title) results")) {
                Label("Share results", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
            }
            .foregroundStyle(Theme.ink)
            .padding(.top, 18)
            .accessibilityHint("Shares each card and its result as a list you can paste into another app.")
        }
    }

    /// Past rounds' winners, newest first.
    @ViewBuilder
    private var history: some View {
        let past = Array((deck.roundHistory ?? []).reversed())
        if !past.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 30)
                        .background(Theme.sunk, in: Circle())
                    Text("Past rounds").font(Theme.display(20, weight: .bold)).foregroundStyle(Theme.ink)
                }
                .accessibilityAddTraits(.isHeader)
                ForEach(past) { result in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(result.question).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(result.at, format: .dateTime.month(.abbreviated).day())
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 14)
        }
    }

    /// Spin for it, when there's more than one match.
    @ViewBuilder
    private var spinBar: some View {
        let options = state.spinCandidates
        if options.count >= 2 {
            let picked = deck.spinCardID.flatMap { id in options.first { $0.id == id } }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(picked.map { "Picked by spin: \($0.title)" } ?? "Can’t choose between \(options.count) matches?")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(picked == nil ? "Let the wheel pick one." : "Everyone sees the same pick.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 6)
                Button(picked == nil ? "Spin" : "Spin again") { session.sheet = .spin(deck.id) }
                    .buttonStyle(.mutual())
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        }
    }

    @ViewBuilder
    private func waiting(me: String?, hasActive: Bool) -> some View {
        let pending = state.cards(.pending)
        let behind = state.participants.compactMap { id -> (String, Int)? in
            let count = pending.filter { state.vote(of: id, on: $0.id) == nil }.count
            return count > 0 ? (id, count) : nil
        }
        if !pending.isEmpty && hasActive && !behind.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Waiting on votes for \(pending.count) card\(pending.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.bold))
                ForEach(behind, id: \.0) { id, count in
                    HStack(spacing: 8) {
                        PlayerDot(player: store.players[id], size: 22)
                        Text("\(id == me ? "You" : store.players[id]?.name ?? "Someone"): \(count) to go")
                            .font(.subheadline)
                        Spacer()
                        if id == me {
                            Button("Keep swiping") { showTab(.swipe) }
                                .buttonStyle(.mutual())
                                .controlSize(.small)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        }
    }

    @ViewBuilder
    private func tier(_ verdict: Verdict, cards: [Card], people n: Int) -> some View {
        let header = HStack(spacing: 10) {
            Image(systemName: verdict.symbol)
                .font(.footnote)
                .foregroundStyle(verdict.color)
                .frame(width: 30, height: 30)
                .background(verdict.soft, in: Circle())
            Text(verdict.title(people: n))
                .font(Theme.display(20, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("\(cards.count)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.muted)
        }
        let rows = VStack(alignment: .leading, spacing: 8) {
            Text(verdict.note).font(.footnote).foregroundStyle(Theme.muted)
            ForEach(cards) { card in
                ResultRow(card: card, state: state, round: inRound)
            }
        }
        if verdict.startsCollapsed {
            DisclosureGroup(isExpanded: Binding(get: { openTiers.contains(verdict) },
                                                set: { if $0 { openTiers.insert(verdict) } else { openTiers.remove(verdict) } })) {
                rows.padding(.top, 6)
            } label: {
                header
            }
            .tint(Theme.muted)
            .padding(.top, 14)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                header.accessibilityAddTraits(.isHeader)
                rows
            }
            .padding(.top, 14)
        }
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ResultRow: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let card: Card
    let state: DeckState
    var round = false

    var body: some View {
        Button {
            session.sheet = .card(card.id)
        } label: {
            HStack(spacing: 12) {
                CardThumb(title: card.title, colorID: card.id, photo: store.coverImage(for: card), size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title).font(.body.weight(.semibold)).lineLimit(1).foregroundStyle(Theme.ink)
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle).font(.footnote).lineLimit(1).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 6)
                FlowLayout(spacing: 4) {
                    ForEach(state.participants, id: \.self) { id in
                        if let vote = state.vote(of: id, on: card.id) {
                            HStack(spacing: 3) {
                                PlayerDot(player: store.players[id], size: 20)
                                Image(systemName: vote.symbol).font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(vote.color)
                            .padding(.leading, 2)
                            .padding(.trailing, 7)
                            .padding(.vertical, 2)
                            .background(vote.soft, in: Capsule())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(store.players[id]?.name ?? "Someone"): \(vote.long(round: round))")
                        }
                    }
                }
                .frame(maxWidth: 140, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        }
        .buttonStyle(.plain)
    }
}
