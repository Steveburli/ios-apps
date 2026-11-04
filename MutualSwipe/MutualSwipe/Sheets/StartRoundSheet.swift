import SwiftUI
import MutualKit

/// Starts a round on a deck: a quick pick for right now, like "Which do you
/// want tonight?". Optionally chains on to other decks, so the group can pick
/// a category, then a food, then a place, each step narrowed by the last.
struct StartRoundSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let deckID: String

    @State private var question = Rounds.defaultQuestion
    /// Decks to go through after this one, in order.
    @State private var chain: [String] = []
    @State private var confirming = false

    /// A chain is this deck plus up to two more.
    private let chainLimit = 2

    var body: some View {
        NavigationStack {
            Group {
                if let deck = store.decks[deckID] {
                    content(deck)
                } else {
                    ContentUnavailableView("This deck was deleted", systemImage: "rectangle.stack.badge.minus")
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Start a round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func content(_ deck: Deck) -> some View {
        let plan = Rounds.plan(vetting: store.state(of: deck.id, me: nil))
        let others = store.decks(in: deck.groupID).filter { $0.id != deck.id }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("A round is a quick pick for right now. Everyone swipes again, just on this round, and what you said in vetting stays as it was.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                Panel {
                    Field(label: "The question", text: $question, placeholder: Rounds.defaultQuestion)
                    Label(planLine(plan), systemImage: plan.usesVetting ? "checkmark.seal" : "rectangle.stack")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Text("In a round, swipe down for “Not tonight”. It hides the card until the next round.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                if !others.isEmpty {
                    Panel {
                        Text("Then narrow it down").font(Theme.display(18, weight: .bold))
                        Text("Optional. Pick up to \(chainLimit) more decks, like a category, then food, then a place. Each step only shows cards that mention what won the step before, when any do.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                        ForEach(others) { other in
                            chainRow(other)
                        }
                    }
                }

                if deck.activeRound != nil {
                    Text("A round is already going. Starting this one saves its winner and clears everyone’s round votes.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                Button {
                    if deck.activeRound != nil { confirming = true } else { start(deck) }
                } label: {
                    Text(plan.cards.count < 2 ? "Add a few cards first" : "Start round with \(plan.cards.count) cards")
                }
                .buttonStyle(.mutual(wide: true))
                .disabled(plan.cards.count < 2 || !store.canWrite(deck.groupID))
                .padding(.top, 4)
            }
            .padding(16)
        }
        .confirmationDialog("Start a new round?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Start a new round", role: .destructive) { start(deck) }
        } message: {
            Text("This clears everyone’s round votes. Vetting votes stay.")
        }
        .onAppear {
            if let asked = deck.roundQuestion, !asked.isEmpty { question = asked }
        }
    }

    private func planLine(_ plan: Rounds.Plan) -> String {
        if plan.usesVetting {
            return "Everyone has vetted this deck, so the round uses the \(plan.cards.count) cards you all liked."
        }
        return "Not everyone has vetted this deck yet, so the round uses all \(plan.cards.count) cards, minus any Nevers."
    }

    private func chainRow(_ other: Deck) -> some View {
        let position = chain.firstIndex(of: other.id)
        return Button {
            if let position {
                chain.remove(at: position)
            } else if chain.count < chainLimit {
                chain.append(other.id)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(position == nil ? Theme.sunk : Theme.accent)
                        .frame(width: 30, height: 30)
                    if let position {
                        Text("\(position + 2)").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accentInk)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(other.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("\(store.cards(in: other.id).count) cards").font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(position == nil && chain.count >= chainLimit)
        .accessibilityLabel(position.map { "\(other.title), step \($0 + 2)" } ?? other.title)
        .accessibilityAddTraits(position == nil ? [] : .isSelected)
    }

    private func start(_ deck: Deck) {
        guard let plan = store.startRound(deck: deck.id, question: question, chain: chain, filter: []) else { return }
        session.vettingShown.remove(deck.id)
        session.show("Round started with \(plan.cards.count) cards")
        dismiss()
    }
}
