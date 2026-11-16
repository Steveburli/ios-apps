import SwiftUI
import MutualKit

/// A picture of who liked what. Each circle is one option, and each person
/// sits inside every circle they liked or super liked. Below it, the cards
/// only one person super liked, each with a Share invite button.
struct OverlapTab: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let deck: Deck
    let state: DeckState
    /// The cards shown as circles. Empty until first shown, then the most-liked cards.
    @State private var shown: [String] = []
    /// The circles tapped: their crossing's people are listed under the picture.
    @State private var selected: Set<Int> = []
    @State private var invite: Invite?

    struct Invite: Identifiable {
        let card: Card
        var id: String { card.id }
    }

    static let circleColors: [Color] = [Theme.palette[2], Theme.palette[1], Theme.palette[0]]
    static let letters = ["A", "B", "C"]

    var body: some View {
        let me = session.me(in: deck.groupID, store: store)
        let cards = shownCards
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if state.activeParticipants.isEmpty {
                    note("Nothing to compare yet. Swipe through the deck, then check back here.")
                } else if cards.isEmpty {
                    note("No one has liked a card yet. Once someone does, it shows up here as a circle.")
                } else {
                    Text("Each circle is an option. People sit inside the ones they liked. Tap a circle or where circles cross to see who’s in it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    VennPicture(cards: cards, state: state, selected: $selected)
                        .frame(maxWidth: .infinity)
                    legend(cards)
                    selection(cards, me: me)
                    nobody(cards, me: me)
                }
                soloLoved(me: me)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .onAppear(perform: fill)
        .onChange(of: state.cards.map(\.id)) { fill() }
        .sheet(item: $invite) { item in
            InviteSheet(message: Overlap.inviteMessage(for: item.card, kind: deck.kind), cardTitle: item.card.title)
        }
    }

    /// The shown cards that still exist, as cards.
    private var shownCards: [Card] {
        let byID = Dictionary(uniqueKeysWithValues: Overlap.options(state).map { ($0.id, $0) })
        return shown.compactMap { byID[$0] }
    }

    /// Starts with the most-liked cards, and drops any that were deleted.
    private func fill() {
        let valid = Set(Overlap.options(state).map(\.id))
        let kept = shown.filter { valid.contains($0) }
        if kept.isEmpty {
            shown = Overlap.startingCards(state)
            selected = []
        } else if kept != shown {
            shown = kept
            selected = []
        }
    }

    // MARK: Legend and swapping

    @ViewBuilder
    private func legend(_ cards: [Card]) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                HStack(spacing: 10) {
                    Text(Self.letters[index])
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Self.circleColors[index], in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        let fans = Overlap.fans(of: card.id, in: state).count
                        Text("\(fans) \(fans == 1 ? "person likes" : "people like") it")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 6)
                    swapMenu(at: index)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Circle \(Self.letters[index]): \(card.title)")
            }
            if cards.count < min(Overlap.maxCircles, Overlap.options(state).count) {
                Menu {
                    ForEach(Overlap.options(state).filter { !shown.contains($0.id) }) { card in
                        Button(card.title) {
                            shown.append(card.id)
                            selected = []
                        }
                    }
                } label: {
                    Label("Add a circle", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tint(Theme.accent)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }

    private func swapMenu(at index: Int) -> some View {
        Menu {
            Section("Swap for") {
                ForEach(Overlap.options(state).filter { !shown.contains($0.id) }) { card in
                    Button(card.title) {
                        shown[index] = card.id
                        selected = []
                    }
                }
            }
            if shown.count > 1 {
                Button(role: .destructive) {
                    shown.remove(at: index)
                    selected = []
                } label: {
                    Label("Remove this circle", systemImage: "minus.circle")
                }
            }
        } label: {
            Text("Swap")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.sunk, in: Capsule())
                .foregroundStyle(Theme.ink)
        }
        .accessibilityLabel("Swap circle \(Self.letters[index])")
    }

    // MARK: Who's in the tapped area

    @ViewBuilder
    private func selection(_ cards: [Card], me: String?) -> some View {
        let picked = selected.sorted().filter { $0 < cards.count }
        if !picked.isEmpty {
            let pickedCards = picked.map { cards[$0] }
            let people = Overlap.people(likingAll: pickedCards.map(\.id), state: state)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(heading(pickedCards, count: people.count))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 6)
                    Button {
                        selected = []
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(Theme.muted).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Close")
                }
                if people.isEmpty {
                    Text("No one is here yet.").font(.footnote).foregroundStyle(Theme.muted)
                }
                ForEach(people, id: \.self) { id in
                    let loved = pickedCards.filter { state.vote(of: id, on: $0.id) == .love }
                    HStack(spacing: 8) {
                        PlayerDot(player: store.players[id], size: 24)
                        Text(name(id, me: me)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        if !loved.isEmpty {
                            Image(systemName: "star.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Vote.love.color)
                            if pickedCards.count > 1 {
                                Text("Super liked \(loved.map(\.title).formatted(.list(type: .and)))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(name(id, me: me) + (loved.isEmpty ? "" : ", super liked"))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
        }
    }

    private func heading(_ cards: [Card], count: Int) -> String {
        let titles = cards.map(\.title).formatted(.list(type: .and))
        return cards.count == 1 ? "Liked \(titles) (\(count))" : "Liked all of \(titles) (\(count))"
    }

    /// People who voted but liked none of the circles.
    @ViewBuilder
    private func nobody(_ cards: [Card], me: String?) -> some View {
        let outside = Overlap.people(in: [], state: state, shown: cards.map(\.id))
            .filter { (state.progress[$0] ?? 0) > 0 }
        if !outside.isEmpty {
            Text("Outside every circle: \(outside.map { name($0, me: me) }.formatted(.list(type: .and)))")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Only you loved this

    @ViewBuilder
    private func soloLoved(me: String?) -> some View {
        let order = (me.map { [$0] } ?? []) + state.participants.filter { $0 != me }
        let lists = order.map { ($0, Overlap.onlyLovedBy($0, in: state)) }
        let mine = lists.first { $0.0 == me }?.1 ?? []
        if lists.contains(where: { !$0.1.isEmpty }) || me != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .font(.footnote)
                        .foregroundStyle(Vote.love.color)
                        .frame(width: 30, height: 30)
                        .background(Vote.love.soft, in: Circle())
                    Text(me == nil ? "Only one person loved these" : "Only you loved this")
                        .font(Theme.display(20, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityAddTraits(.isHeader)
                Text("Super likes no one else in the group liked. Invite someone else to do it with you.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                if me != nil && mine.isEmpty {
                    note("Nothing yet. When you super like something no one else here likes, it shows up here.")
                }
                ForEach(lists, id: \.0) { person, cards in
                    if !cards.isEmpty {
                        if person != me {
                            HStack(spacing: 8) {
                                PlayerDot(player: store.players[person], size: 22)
                                Text("Only \(name(person, me: me)) loved")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.ink)
                            }
                            .padding(.top, 6)
                        }
                        ForEach(cards) { card in
                            soloRow(card)
                        }
                    }
                }
            }
            .padding(.top, 14)
        }
    }

    private func soloRow(_ card: Card) -> some View {
        HStack(spacing: 12) {
            Button {
                session.sheet = .card(card.id)
            } label: {
                HStack(spacing: 12) {
                    CardThumb(title: card.title, colorID: card.id, photo: StarterPhoto.image(for: card), size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.title).font(.body.weight(.semibold)).lineLimit(1).foregroundStyle(Theme.ink)
                        if !card.subtitle.isEmpty {
                            Text(card.subtitle).font(.footnote).lineLimit(1).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                invite = Invite(card: card)
            } label: {
                Label("Share invite", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.sunk, in: Circle())
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityLabel("Share invite for \(card.title)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }

    // MARK: Helpers

    private func name(_ id: String, me: String?) -> String {
        id == me ? "You" : store.players[id]?.name ?? "Someone"
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One to three overlapping circles, with each person's dot in the area that
/// matches exactly the circles they liked.
private struct VennPicture: View {
    @Environment(CloudStore.self) private var store
    let cards: [Card]
    let state: DeckState
    @Binding var selected: Set<Int>

    private static let dot: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let layout = VennLayout(count: cards.count, size: proxy.size)
            let inside = Overlap.membership(state, shown: cards.map(\.id))
            let areas = Dictionary(grouping: state.participants.filter { !(inside[$0] ?? []).isEmpty }) { inside[$0] ?? [] }
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for (index, circle) in layout.circles.enumerated() {
                        let color = OverlapTab.circleColors[index]
                        context.fill(Path(ellipseIn: circle), with: .color(color.opacity(0.14)))
                    }
                    if !selected.isEmpty {
                        context.fill(layout.path(for: selected), with: .color(Theme.accent.opacity(0.22)))
                    }
                    for (index, circle) in layout.circles.enumerated() {
                        context.stroke(Path(ellipseIn: circle), with: .color(OverlapTab.circleColors[index]), lineWidth: 2.5)
                    }
                }
                ForEach(Array(layout.circles.enumerated()), id: \.offset) { index, _ in
                    let spot = layout.letterSpot(index)
                    Text(OverlapTab.letters[index])
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(OverlapTab.circleColors[index], in: Circle())
                        .position(spot)
                }
                ForEach(Array(areas.keys), id: \.self) { area in
                    if let spot = layout.anchors[area] {
                        DotCluster(people: areas[area] ?? [], state: state, cards: cards, area: area,
                                   room: spot.room, dot: Self.dot)
                            .position(spot.point)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let hit = layout.area(at: location)
                withAnimation(.easeOut(duration: 0.18)) {
                    selected = hit.isEmpty || hit == selected ? [] : hit
                }
            }
        }
        .aspectRatio(cards.count == 3 ? 1.02 : cards.count == 2 ? 1.6 : 1.4, contentMode: .fit)
        .frame(maxWidth: 380)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    /// What VoiceOver reads: who's in each circle.
    private var summary: String {
        cards.enumerated().map { index, card in
            let names = Overlap.fans(of: card.id, in: state).map { store.players[$0]?.name ?? "Someone" }
            return "Circle \(OverlapTab.letters[index]), \(card.title): " + (names.isEmpty ? "no one" : names.formatted(.list(type: .and)))
        }
        .joined(separator: ". ")
    }
}

/// People's dots packed into one area, with "+n" when they don't all fit.
private struct DotCluster: View {
    @Environment(CloudStore.self) private var store
    let people: [String]
    let state: DeckState
    let cards: [Card]
    let area: Set<Int>
    let room: CGFloat
    let dot: CGFloat

    var body: some View {
        let spacing: CGFloat = 2
        let perRow = max(1, Int((room * 1.5 + spacing) / (dot + spacing)))
        let rows = max(1, Int((room * 1.3 + spacing) / (dot + spacing)))
        let capacity = perRow * rows
        let showing = people.count > capacity ? Array(people.prefix(max(0, capacity - 1))) : people
        let extra = people.count - showing.count
        // nil stands for the "+n" chip.
        let items: [String?] = showing.map { Optional($0) } + (extra > 0 ? [nil] : [])
        let lines = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
        VStack(spacing: spacing) {
            ForEach(lines.indices, id: \.self) { line in
                HStack(spacing: spacing) {
                    ForEach(lines[line].indices, id: \.self) { slot in
                        if let id = lines[line][slot] {
                            face(id)
                        } else {
                            Text("+\(extra)")
                                .font(.system(size: dot * 0.42, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.ink)
                                .frame(width: dot, height: dot)
                                .background(Theme.surface, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.line))
                        }
                    }
                }
            }
        }
        .fixedSize()
        .allowsHitTesting(false)
    }

    /// A person's dot, with a star if they super liked any circle they're in here.
    private func face(_ id: String) -> some View {
        PlayerDot(player: store.players[id], size: dot)
            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if area.contains(where: { $0 < cards.count && state.vote(of: id, on: cards[$0].id) == .love }) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Vote.love.color)
                        .offset(x: 4, y: -4)
                }
            }
    }
}

/// Where the circles sit, and the best spot inside each area for its dots.
private struct VennLayout {
    struct Spot {
        let point: CGPoint
        /// Distance from the spot to the nearest edge of its area.
        let room: CGFloat
    }

    let circles: [CGRect]
    let anchors: [Set<Int>: Spot]
    private let centers: [CGPoint]
    private let radius: CGFloat

    init(count: Int, size: CGSize) {
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        var centers: [CGPoint] = []
        var r: CGFloat
        switch count {
        case 3:
            // Three circles in a triangle. The picture spans about 3.1r wide and 2.95r tall.
            r = min(size.width / 3.15, size.height / 2.98)
            let d = r * 0.62
            let center = CGPoint(x: mid.x, y: mid.y - r * 0.155)
            for angle in [-150.0, -30.0, 90.0] {
                let a = angle * .pi / 180
                centers.append(CGPoint(x: center.x + d * cos(a), y: center.y + d * sin(a)))
            }
        case 2:
            r = min(size.width / 3.3, size.height / 2.1)
            centers = [CGPoint(x: mid.x - r * 0.6, y: mid.y), CGPoint(x: mid.x + r * 0.6, y: mid.y)]
        default:
            r = min(size.width, size.height) / 2.1
            centers = count > 0 ? [mid] : []
        }
        self.radius = r
        self.centers = centers
        self.circles = centers.map { CGRect(x: $0.x - r, y: $0.y - r, width: r * 2, height: r * 2) }

        // Sample a grid and keep, for each area, the point farthest from any edge.
        var best: [Set<Int>: Spot] = [:]
        let steps = 70
        let bounds = circles.reduce(CGRect.null) { $0.union($1) }
        if !bounds.isNull {
            for i in 0...steps {
                for j in 0...steps {
                    let p = CGPoint(x: bounds.minX + bounds.width * CGFloat(i) / CGFloat(steps),
                                    y: bounds.minY + bounds.height * CGFloat(j) / CGFloat(steps))
                    var area = Set<Int>()
                    var room = CGFloat.greatestFiniteMagnitude
                    for (index, c) in centers.enumerated() {
                        let distance = hypot(p.x - c.x, p.y - c.y)
                        if distance < r { area.insert(index) }
                        room = min(room, abs(r - distance))
                    }
                    guard !area.isEmpty else { continue }
                    if room > (best[area]?.room ?? -1) {
                        best[area] = Spot(point: p, room: room)
                    }
                }
            }
        }
        self.anchors = best
    }

    /// The circles a point is inside.
    func area(at point: CGPoint) -> Set<Int> {
        Set(centers.indices.filter { hypot(point.x - centers[$0].x, point.y - centers[$0].y) < radius })
    }

    /// Everywhere inside every circle in `area`: what a tap highlights.
    func path(for area: Set<Int>) -> Path {
        var shape: Path?
        for index in area.sorted() where index < circles.count {
            let next = Path(ellipseIn: circles[index])
            shape = shape.map { $0.intersection(next) } ?? next
        }
        return shape ?? Path()
    }

    /// Where a circle's letter sits: on its outer edge, away from the others.
    func letterSpot(_ index: Int) -> CGPoint {
        let c = centers[index]
        guard centers.count > 1 else { return CGPoint(x: c.x, y: c.y - radius * 0.84) }
        let middle = CGPoint(x: centers.map(\.x).reduce(0, +) / CGFloat(centers.count),
                             y: centers.map(\.y).reduce(0, +) / CGFloat(centers.count))
        let dx = c.x - middle.x, dy = c.y - middle.y
        let length = max(hypot(dx, dy), 0.001)
        return CGPoint(x: c.x + dx / length * radius * 0.84, y: c.y + dy / length * radius * 0.84)
    }
}

/// Writes an invite for a card only one person loved. You can edit it, then
/// send it with the iPhone share sheet to whoever you like.
private struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message: String
    let cardTitle: String

    init(message: String, cardTitle: String) {
        _message = State(initialValue: message)
        self.cardTitle = cardTitle
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit the message if you like, then pick who to send it to. It only names \(cardTitle), nothing about your group.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                TextEditor(text: $message)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 160)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
                ShareLink(item: message.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.mutual(wide: true))
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Invite someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
