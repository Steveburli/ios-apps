import SwiftUI
import MutualKit

/// A wheel for when you all agree on too many things. It spins over every
/// Super match and Match, lands on one, and saves the winner with the deck so
/// every phone shows the same pick.
struct SpinSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let deckID: String

    @State private var angle: Double = 0
    @State private var spinning = false
    @State private var winnerID: String?
    /// Winners set aside with "Spin without it".
    @State private var setAside: Set<String> = []

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
            .navigationTitle("Spin for it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func content(_ deck: Deck) -> some View {
        let me = session.me(in: deck.groupID, store: store)
        let state = store.state(of: deck.id, me: me)
        let options = state.spinCandidates.filter { !setAside.contains($0.id) }
        let winner = winnerID.flatMap { store.cards[$0] }

        return ScrollView {
            VStack(spacing: 18) {
                Text(options.count < 2 && winner == nil
                     ? "The spinner needs at least two matches."
                     : "\(options.count) matches on the wheel. Tap Spin and let it decide.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)

                ZStack(alignment: .top) {
                    Wheel(cards: options, angle: angle)
                        .frame(width: 300, height: 300)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.ink)
                        .offset(y: -14)
                        .accessibilityHidden(true)
                }
                .padding(.top, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spinning ? "Spinning" : "Wheel with \(options.count) matches")

                if let winner, !spinning {
                    VStack(spacing: 8) {
                        Text("PICKED BY SPIN")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.muted)
                        Text(winner.title)
                            .font(Theme.display(30))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.ink)
                        if !winner.subtitle.isEmpty {
                            Text(winner.subtitle).font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        Text("Just for fun. Everyone in the group sees this pick, and you can still choose something else.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        FlowLayout {
                            Button("See the card") { session.sheet = .card(winner.id) }
                                .buttonStyle(.mutual(.quiet))
                            if !deck.decidedCards.contains(winner.id) {
                                Button("Mark as decided") {
                                    let name = me.flatMap { store.players[$0]?.name }
                                    store.setDecided(true, card: winner.id, by: name)
                                    session.markDecisionSeen(deck)
                                    session.show("“\(winner.title)” is decided")
                                }
                                .buttonStyle(.mutual())
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
                    .accessibilityElement(children: .contain)
                }

                FlowLayout {
                    Button(winner == nil ? "Spin" : "Spin again") { spin(options, deck: deck) }
                        .buttonStyle(.mutual())
                        .disabled(spinning || options.count < 2)
                    if let winner, !spinning, options.count > 2 {
                        Button("Spin without it") {
                            setAside.insert(winner.id)
                            winnerID = nil
                            spin(options.filter { $0.id != winner.id }, deck: deck)
                        }
                        .buttonStyle(.mutual(.quiet))
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            // Pick up the group's last spin, if it's still on the wheel.
            if winnerID == nil, let saved = deck.spinCardID, options.contains(where: { $0.id == saved }) {
                winnerID = saved
                if let index = options.firstIndex(where: { $0.id == saved }) {
                    angle = Wheel.angle(landingOn: index, of: options.count)
                }
            }
        }
    }

    private func spin(_ options: [Card], deck: Deck) {
        guard options.count >= 2, let index = options.indices.randomElement() else { return }
        let target = Wheel.angle(landingOn: index, of: options.count)
        // Whole turns plus the way to the winner, always forward.
        let turns = (angle / 360).rounded(.down) + 5
        var next = turns * 360 + target
        if next <= angle + 720 { next += 360 }
        spinning = true
        winnerID = options[index].id
        withAnimation(.timingCurve(0.12, 0.8, 0.2, 1, duration: 3.4)) {
            angle = next
        } completion: {
            spinning = false
            store.setSpin(options[index].id, deck: deck.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// The wheel: one colored slice per card, labeled when there's room.
struct Wheel: View {
    let cards: [Card]
    let angle: Double

    /// The wheel rotation that puts slice `index` under the pointer at the top.
    static func angle(landingOn index: Int, of count: Int) -> Double {
        let slice = 360 / Double(max(count, 1))
        let center = slice * (Double(index) + 0.5)
        return (360 - center).truncatingRemainder(dividingBy: 360)
    }

    var body: some View {
        let count = max(cards.count, 1)
        let slice = 360 / Double(count)
        ZStack {
            if cards.isEmpty {
                Circle().fill(Theme.sunk)
            }
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                SliceShape(start: .degrees(slice * Double(index) - 90), end: .degrees(slice * Double(index + 1) - 90))
                    .fill(Theme.cardColor(card.id))
                    .overlay(SliceShape(start: .degrees(slice * Double(index) - 90), end: .degrees(slice * Double(index + 1) - 90))
                        .stroke(Color.white.opacity(0.6), lineWidth: 2))
                Text(count <= 10 ? card.title : CardText.initial(card.title))
                    .font(.system(size: count <= 6 ? 14 : 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .trailing)
                    .offset(x: 62)
                    .rotationEffect(.degrees(slice * (Double(index) + 0.5) - 90))
            }
            Circle()
                .fill(Theme.surface)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 2))
        }
        .rotationEffect(.degrees(angle))
    }
}

private struct SliceShape: Shape {
    let start: Angle
    let end: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2, startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}
