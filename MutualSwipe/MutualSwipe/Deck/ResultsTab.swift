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

                ForEach(Verdict.shown, id: \.self) { verdict in
                    let cards = state.cards(verdict)
                    if !cards.isEmpty {
                        tier(verdict, cards: cards, people: n)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
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
                ResultRow(card: card, state: state)
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

    var body: some View {
        Button {
            session.sheet = .card(card.id)
        } label: {
            HStack(spacing: 12) {
                Text(CardText.initial(card.title))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.cardColor(card.id), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
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
                            .accessibilityLabel("\(store.players[id]?.name ?? "Someone"): \(vote.long)")
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
