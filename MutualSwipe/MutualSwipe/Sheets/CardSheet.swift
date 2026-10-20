import SwiftUI
import MutualKit

/// A card's details, your vote, and everyone else's once you've voted.
struct CardSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let cardID: String

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
    }

    private func content(_ card: Card, deck: Deck) -> some View {
        let me = session.me(in: deck.groupID, store: store)
        let state = store.state(of: deck.id, me: me)
        let mine = me.flatMap { state.vote(of: $0, on: card.id) }
        let others = state.participants.filter { $0 != me && state.vote(of: $0, on: card.id) != nil }
        let verdict = state.verdict(for: card)

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
                .background {
                    ZStack {
                        Theme.cardColor(card.id)
                        RadialGradient(colors: [Color.white.opacity(0.17), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
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

                heading("Your vote")
                if let me {
                    HStack(spacing: 8) {
                        ForEach([Vote.never, .nope, .like, .love]) { vote in
                            Button {
                                guard store.canWrite(deck.groupID) else {
                                    session.show(Session.readOnlyMessage)
                                    return
                                }
                                store.setVote(vote, card: card.id, player: me)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: vote.symbol).foregroundStyle(vote.color)
                                    Text(vote.label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink)
                                }
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(mine == vote ? vote.soft : Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(mine == vote ? vote.color : Theme.line, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(vote.long)
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
                                    Label(vote.long, systemImage: vote.symbol)
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
            }
            .padding(16)
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
