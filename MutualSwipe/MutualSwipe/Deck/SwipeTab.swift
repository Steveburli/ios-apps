import SwiftUI
import MutualKit

/// The card stack: drag right to like, left to reject, up to super like,
/// down to super reject. The four buttons do the same.
struct SwipeTab: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let deck: Deck
    let state: DeckState
    let showTab: (Session.DeckTab) -> Void

    @State private var drag: CGSize = .zero
    @State private var flying: (cardID: String, vote: Vote)?
    @State private var voteCount = 0
    @State private var stackSize = CGSize(width: 400, height: 600)

    private var me: String? { session.me(in: deck.groupID, store: store) }

    var body: some View {
        let total = state.cards.count
        let done = total - state.queue.count
        VStack(spacing: 12) {
            if me != nil && total > 0 {
                HStack(spacing: 10) {
                    (Text("\(done)").bold().foregroundStyle(Theme.ink) + Text(" / \(total)"))
                    ProgressView(value: Double(done), total: Double(max(1, total)))
                        .tint(Theme.accent)
                    Text("\(state.queue.count) left")
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.muted)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(done) of \(total) swiped, \(state.queue.count) left")
            }

            GeometryReader { proxy in
                stack(size: proxy.size)
                    .onAppear { stackSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in stackSize = size }
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(maxWidth: 410, minHeight: 320, maxHeight: 640)
            .frame(maxWidth: .infinity)

            if showingCards {
                controls
            }

            HStack {
                Text("← nope · → like · ↑ love · ↓ never")
                    .accessibilityHidden(true)
                Spacer()
                Button {
                    undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!canUndo)
                .font(.footnote.weight(.semibold))
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .sensoryFeedback(.impact(weight: .light), trigger: voteCount)
    }

    private var showingCards: Bool {
        me != nil && !state.queue.isEmpty
    }

    private var canUndo: Bool {
        guard let me else { return false }
        return store.canWrite(deck.groupID) && session.canUndo(deck: deck.id, player: me)
    }

    // MARK: Stack

    @ViewBuilder
    private func stack(size: CGSize) -> some View {
        if me == nil {
            StackMessage {
                Text("Who’s swiping?").font(Theme.display(25, weight: .bold))
                Text("Pick your name so your votes count as yours.").foregroundStyle(Theme.muted)
                Button("Choose your name") { session.sheet = .player(deck.groupID) }
                    .buttonStyle(.mutual(.quiet))
            }
        } else if state.cards.isEmpty {
            StackMessage {
                Text("No cards yet").font(Theme.display(25, weight: .bold))
                Text("Add some on the Cards tab.").foregroundStyle(Theme.muted)
                Button("Add cards") { showTab(.cards) }
                    .buttonStyle(.mutual(.quiet))
            }
        } else if state.queue.isEmpty {
            StackMessage {
                BrandMark().scaleEffect(1.8).padding(.bottom, 8)
                Text("You’ve swiped all \(state.cards.count)").font(Theme.display(25, weight: .bold))
                Text(doneLine).foregroundStyle(Theme.muted)
                Button("See results") { showTab(.results) }
                    .buttonStyle(.mutual(.quiet))
            }
        } else {
            let top = Array(state.queue.prefix(3))
            ZStack {
                ForEach(Array(top.enumerated()).reversed(), id: \.element.id) { index, card in
                    cardLayer(card, index: index, size: size)
                }
            }
        }
    }

    private var doneLine: String {
        let others = state.participants.filter { $0 != me }
        if others.isEmpty { return "Nobody else has swiped this deck yet. Invite them from the home screen, or pass the phone." }
        let waiting = others.compactMap { id -> String? in
            let left = state.remaining(for: id)
            return left > 0 ? "\(store.players[id]?.name ?? "Someone") (\(left) left)" : nil
        }
        return waiting.isEmpty ? "Everyone is done, so the results are final." : "Still swiping: \(waiting.joined(separator: ", "))."
    }

    @ViewBuilder
    private func cardLayer(_ card: Card, index: Int, size: CGSize) -> some View {
        // While the top card flies off, the next one moves up into its place.
        let position = flying != nil && index > 0 ? index - 1 : index
        let isTop = index == 0
        CardFace(card: card, kind: deck.kind, stamp: isTop ? stamp : nil)
            .frame(width: size.width, height: max(0, size.height - 20))
            .scaleEffect(position == 0 ? 1 : position == 1 ? 0.95 : 0.9)
            .offset(y: position == 0 ? 0 : position == 1 ? 12 : 24)
            .offset(isTop ? drag : .zero)
            .rotationEffect(.degrees(isTop ? drag.width * 0.05 : 0))
            .allowsHitTesting(isTop && flying == nil)
            .gesture(dragGesture(card, size: size))
            .onTapGesture { if isTop { session.sheet = .card(card.id) } }
            .accessibilityHidden(!isTop)
            .accessibilityHint("Double-tap for details. Swipe up or down for actions.")
            .accessibilityActions {
                ForEach(Vote.allCases) { vote in
                    Button(vote.long) { fling(card, vote, size: size) }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: position)
            .zIndex(Double(3 - index))
    }

    /// Which stamp shows on the top card, and how strongly.
    private var stamp: (vote: Vote, opacity: Double)? {
        if let flying { return (flying.vote, 1) }
        guard drag != .zero else { return nil }
        let vote = Self.direction(drag)
        let distance = vote == .like || vote == .nope ? abs(drag.width) : abs(drag.height)
        return (vote, min(1, max(0, (distance - 15) / 90)))
    }

    static func direction(_ offset: CGSize) -> Vote {
        if abs(offset.height) > abs(offset.width) { return offset.height < 0 ? .love : .never }
        return offset.width > 0 ? .like : .nope
    }

    private func dragGesture(_ card: Card, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard flying == nil else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard flying == nil else { return }
                let vote = Self.direction(value.translation)
                let horizontal = vote == .like || vote == .nope
                let distance = horizontal ? abs(value.translation.width) : abs(value.translation.height)
                let projected = horizontal ? abs(value.predictedEndTranslation.width) : abs(value.predictedEndTranslation.height)
                let need = horizontal ? min(110, size.width * 0.28) : min(120, size.height * 0.2)
                if distance > need || (distance > 40 && projected > need * 2) {
                    fling(card, vote, size: size)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { drag = .zero }
                }
            }
    }

    // MARK: Voting

    private var controls: some View {
        HStack(alignment: .bottom, spacing: 20) {
            control(.never, big: false)
            control(.nope, big: true)
            control(.like, big: true)
            control(.love, big: false)
        }
        .frame(maxWidth: .infinity)
    }

    private func control(_ vote: Vote, big: Bool) -> some View {
        Button {
            if let card = state.queue.first { fling(card, vote, size: stackSize) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: vote.symbol)
                    .font(.system(size: big ? 28 : 23, weight: .bold))
                    .foregroundStyle(vote.color)
                    .frame(width: big ? 66 : 54, height: big ? 66 : 54)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                Text(vote.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .buttonStyle(.plain)
        .disabled(flying != nil)
        .accessibilityLabel(vote == .love ? "Love: super like" : vote == .never ? "Never: super reject" : vote == .nope ? "Nope: reject" : "Like")
    }

    private func fling(_ card: Card, _ vote: Vote, size: CGSize) {
        guard flying == nil, let me else { return }
        guard store.canWrite(deck.groupID) else {
            session.show(Session.readOnlyMessage)
            withAnimation { drag = .zero }
            return
        }
        flying = (card.id, vote)
        let far = max(size.width, size.height) * 1.4
        let target: CGSize
        switch vote {
        case .like: target = CGSize(width: far, height: drag.height)
        case .nope: target = CGSize(width: -far, height: drag.height)
        case .love: target = CGSize(width: drag.width, height: -far)
        case .never: target = CGSize(width: drag.width, height: far)
        }
        let duration = reduceMotion ? 0.06 : 0.3
        withAnimation(.easeIn(duration: duration)) { drag = target }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            store.setVote(vote, card: card.id, player: me)
            session.pushUndo(card: card.id, deck: deck.id, player: me)
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                drag = .zero
                flying = nil
            }
            voteCount += 1
        }
    }

    private func undo() {
        guard let me, let cardID = session.popUndo(deck: deck.id, player: me) else { return }
        store.setVote(nil, card: cardID, player: me)
    }
}

/// A message where the stack would be.
private struct StackMessage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.ink)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
        .padding(.bottom, 20)
    }
}

/// The colored card: a big faded initial, the title, quick facts, details and tags.
struct CardFace: View {
    let card: Card
    let kind: DeckKind
    var stamp: (vote: Vote, opacity: Double)?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack(alignment: .topLeading) {
            Theme.cardColor(card.id)
            RadialGradient(colors: [Color.white.opacity(0.17), .clear], center: .topLeading, startRadius: 0, endRadius: 420)
            Text(CardText.initial(card.title))
                .font(.system(size: 260, weight: .black))
                .foregroundStyle(Color.white.opacity(0.14))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 8, y: -40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(kind.label.uppercased())
                    Spacer()
                    if !card.link.isEmpty { Text("LINK INSIDE") }
                }
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .opacity(0.88)
                Spacer(minLength: 0)
                Text(card.title)
                    .font(.system(size: 36, weight: .heavy))
                    .minimumScaleFactor(0.6)
                    .lineLimit(4)
                if !card.subtitle.isEmpty {
                    Text(card.subtitle).font(.subheadline.weight(.semibold)).opacity(0.95)
                }
                if !card.details.isEmpty {
                    Text(card.details).font(.subheadline).lineLimit(4).opacity(0.94)
                }
                if !card.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(card.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.2), in: Capsule())
                        }
                    }
                }
                Text("Tap for details").font(.caption.weight(.semibold)).opacity(0.72)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 22)
        }
        .clipShape(shape)
        .overlay { stampView }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 18)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([card.title, card.subtitle, card.details].filter { !$0.isEmpty }.joined(separator: ". "))
    }

    @ViewBuilder
    private var stampView: some View {
        if let stamp {
            let vote = stamp.vote
            Text(vote.stamp)
                .font(.system(size: 30, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(vote.stampColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(vote.stampColor, lineWidth: 4))
                .rotationEffect(.degrees(vote == .like ? -14 : vote == .nope ? 14 : vote == .love ? -7 : 7))
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: vote == .like ? .topLeading : vote == .nope ? .topTrailing : .center)
                .padding(30)
                .opacity(stamp.opacity)
                .allowsHitTesting(false)
        }
    }
}
