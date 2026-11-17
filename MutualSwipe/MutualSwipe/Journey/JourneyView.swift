import SwiftUI
import CoreLocation
import MutualKit

/// "Plan something new": one question per screen, then a swipe through broad
/// categories, then the specific places from the ones you liked become a
/// deck the whole group swipes on.
struct JourneyView: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable {
        case plan, crowd, budget, distance, when, avoid, vibe, categories, places
    }

    @State private var step: Step = .plan
    @State private var forward = true
    @State private var answers = Journey.Answers()
    /// Category swipes: true is a yes.
    @State private var swipes: [String: Bool] = [:]
    @State private var places: [Journey.Place] = []
    @State private var kept: Set<String> = []
    @State private var title = ""
    @State private var loading = false
    @State private var mapsNote: String?
    @State private var location = OneLocation()

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                content
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Theme.bg.ignoresSafeArea())
        .interactiveDismissDisabled(step.rawValue > Step.plan.rawValue)
    }

    // MARK: Header: back, progress, close

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                go(to: Step(rawValue: step.rawValue - 1) ?? .plan)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
            }
            .opacity(step == .plan ? 0 : 1)
            .disabled(step == .plan)
            .accessibilityLabel("Back")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.sunk)
                    Capsule().fill(Theme.heroGradient)
                        .frame(width: max(10, geo.size.width * progress))
                }
            }
            .frame(height: 8)
            .animation(.easeOut(duration: 0.3), value: step)
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var progress: CGFloat {
        CGFloat(step.rawValue + 1) / CGFloat(Step.allCases.count)
    }

    // MARK: The screens

    @ViewBuilder
    private var content: some View {
        switch step {
        case .plan:
            ChoiceScreen(eyebrow: "Let’s plan something", question: "What are you deciding?",
                         options: Journey.Plan.allCases, selected: [answers.plan],
                         title: { $0.title }, detail: { $0.detail }, symbol: { $0.symbol }) { plan in
                answers.plan = plan
                swipes = [:]
                next()
            }
        case .crowd:
            ChoiceScreen(eyebrow: "The basics", question: "Who’s it for?",
                         options: Journey.Crowd.allCases, selected: [answers.crowd],
                         title: { $0.title }, detail: { _ in nil }, symbol: { $0.symbol }) { crowd in
                answers.crowd = crowd
                next()
            }
        case .budget:
            ChoiceScreen(eyebrow: "A few quick questions", question: "What’s the budget?",
                         options: Journey.Budget.allCases, selected: [answers.budget],
                         title: { $0.title }, detail: { _ in nil }, symbol: { $0.symbol }) { budget in
                answers.budget = budget
                next()
            }
        case .distance:
            ChoiceScreen(eyebrow: "A few quick questions", question: "How far will you go?",
                         options: Journey.Distance.allCases, selected: [answers.distance],
                         title: { $0.title }, detail: { $0.detail }, symbol: { $0.symbol }) { distance in
                answers.distance = distance
                next()
            }
        case .when:
            ChoiceScreen(eyebrow: "A few quick questions", question: "When is it?",
                         options: Journey.When.allCases, selected: [answers.when],
                         title: { $0.title }, detail: { _ in nil }, symbol: { $0.symbol }) { when in
                answers.when = when
                next()
            }
        case .avoid:
            ChoiceScreen(eyebrow: "Almost there", question: "Anything to skip?", note: "Pick any, or none.",
                         options: Journey.Avoid.allCases, selected: answers.avoid,
                         title: { $0.title }, detail: { _ in nil }, symbol: { $0.symbol },
                         nextTitle: answers.avoid.isEmpty ? "Nothing to skip" : "Next") { avoid in
                answers.avoid.formSymmetricDifference([avoid])
            } onNext: {
                next()
            }
        case .vibe:
            ChoiceScreen(eyebrow: "The vibe", question: "What are you in the mood for?", note: "Pick one or more.",
                         options: Journey.Vibe.allCases, selected: answers.vibes,
                         title: { $0.title }, detail: { _ in nil }, symbol: { $0.symbol }, grid: true,
                         nextTitle: answers.vibes.isEmpty ? "Surprise me" : "Next") { vibe in
                answers.vibes.formSymmetricDifference([vibe])
            } onNext: {
                swipes = [:]
                next()
            }
        case .categories:
            CategorySwipe(categories: Journey.categories(for: answers), plan: answers.plan, swipes: $swipes) {
                Task { await gatherPlaces() }
                next()
            }
        case .places:
            placesScreen
        }
    }

    // MARK: The last screen: specific places

    private var liked: [Journey.Category] {
        Journey.categories(for: answers).filter { swipes[$0.id] == true }
    }

    private var placesScreen: some View {
        let categories = liked
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR DECK")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.accent)
                    Text("Here’s what we found")
                        .font(Theme.display(30))
                        .foregroundStyle(Theme.ink)
                    Text("Untick anything you’d never do. Everyone in your group then swipes on the rest, and Mutual shows what you all agree on.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                Field(label: "Deck name", text: $title, placeholder: Journey.deckTitle(for: answers))

                if categories.isEmpty {
                    Text("You didn’t say yes to any category. Go back and swipe again.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(categories) { category in
                    let mine = places.filter { $0.categoryID == category.id }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(category.title, systemImage: category.symbol)
                            .font(Theme.display(19, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        if mine.isEmpty {
                            Text(loading ? "Looking nearby…" : "Nothing nearby fits. Try “Worth a drive” or a bigger budget.")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                        ForEach(mine) { place in
                            PlaceRow(place: place, isOn: kept.contains(place.id)) {
                                if kept.contains(place.id) { kept.remove(place.id) } else { kept.insert(place.id) }
                            }
                        }
                    }
                }
                if loading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Checking Apple Maps near you…").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                if let mapsNote {
                    Text(mapsNote).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                make()
            } label: {
                Text(keptPlaces.isEmpty ? "Pick at least one place" : "Make the deck · \(keptPlaces.count) card\(keptPlaces.count == 1 ? "" : "s")")
            }
            .buttonStyle(.mutual(wide: true))
            .disabled(keptPlaces.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.bg.opacity(0.95))
        }
    }

    private var keptPlaces: [Journey.Place] {
        places.filter { kept.contains($0.id) }
    }

    /// Indy places right away, then Apple Maps fills the gaps.
    private func gatherPlaces() async {
        let categories = liked
        let indy = Journey.indyPlaces(for: categories, answers: answers)
        places = indy
        kept = Set(indy.map(\.id))
        mapsNote = nil
        guard !Screenshots.isActive, categories.contains(where: { !$0.mapsQueries.isEmpty }) else { return }
        loading = true
        defer { loading = false }
        guard let here = await location.current() else {
            mapsNote = location.isRefused
                ? "Mutual can add real places near you from Apple Maps. Turn on Location for Mutual in Settings to see them."
                : "Couldn’t find where you are, so these are from Mutual’s Indianapolis list."
            return
        }
        // Far from Indianapolis, the Indy list doesn't help: use Maps for everything.
        let nearIndy = here.distance(from: NearbyPlaces.indy) < NearbyPlaces.indyReach
        let base = nearIndy ? indy : []
        var counts: [String: Int] = [:]
        for place in base { counts[place.categoryID, default: 0] += 1 }
        let found = await NearbyPlaces.places(for: categories, indyCounts: counts, answers: answers, near: here,
                                              skipping: Set(base.map(\.draft.title)))
        let all = base + found
        // Keep each category's places together, Indy first.
        places = categories.flatMap { category in all.filter { $0.categoryID == category.id } }
        kept = Set(places.map(\.id))
        if found.isEmpty && !nearIndy {
            mapsNote = "Apple Maps didn’t find matches nearby. Try a different distance."
        }
    }

    private func make() {
        let group = session.group(in: store) ?? store.ensureGroup()
        guard store.canWrite(group.id) else {
            session.show(Session.readOnlyMessage)
            return
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let deck = store.createDeck(in: group.id, title: name.isEmpty ? Journey.deckTitle(for: answers) : name,
                                          kind: answers.plan.kind, blurb: Journey.deckBlurb(for: answers)) else { return }
        let added = store.addCards(keptPlaces.map(\.draft), to: deck.id)
        session.currentGroupID = group.id
        session.openingTab[deck.id] = .swipe
        session.path = [deck.id]
        session.journeyMade = JourneyMade(deckID: deck.id, groupID: group.id, cards: added)
        dismiss()
    }

    // MARK: Moving between steps

    private func next() {
        go(to: Step(rawValue: step.rawValue + 1) ?? .places)
    }

    private func go(to target: Step) {
        forward = target.rawValue > step.rawValue
        if target == .categories { swipes = [:] }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            step = target
        }
    }
}

/// What the journey just made, so the deck can offer to send it.
struct JourneyMade: Equatable {
    let deckID: String
    let groupID: String
    let cards: Int
}

// MARK: - One question, big tap targets

private struct ChoiceScreen<Option: Hashable & Identifiable>: View {
    let eyebrow: String
    let question: String
    var note: String? = nil
    let options: [Option]
    let selected: Set<Option>
    let title: (Option) -> String
    let detail: (Option) -> String?
    let symbol: (Option) -> String
    var grid = false
    /// Multi-select screens show a Next button. Single-select ones move on when tapped.
    var nextTitle: String? = nil
    let onPick: (Option) -> Void
    var onNext: (() -> Void)? = nil

    init(eyebrow: String, question: String, note: String? = nil, options: [Option], selected: Set<Option>,
         title: @escaping (Option) -> String, detail: @escaping (Option) -> String?, symbol: @escaping (Option) -> String,
         grid: Bool = false, nextTitle: String? = nil, onPick: @escaping (Option) -> Void, onNext: (() -> Void)? = nil) {
        self.eyebrow = eyebrow
        self.question = question
        self.note = note
        self.options = options
        self.selected = selected
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.grid = grid
        self.nextTitle = nextTitle
        self.onPick = onPick
        self.onNext = onNext
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow.uppercased())
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.accent)
                    Text(question)
                        .font(Theme.display(32))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let note {
                        Text(note).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                }
                if grid {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(options) { option in tile(option, compact: true) }
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(options) { option in tile(option, compact: false) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .safeAreaInset(edge: .bottom) {
            if let nextTitle, let onNext {
                Button(nextTitle, action: onNext)
                    .buttonStyle(.mutual(wide: true))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.bg.opacity(0.95))
            }
        }
    }

    private func tile(_ option: Option, compact: Bool) -> some View {
        let isOn = selected.contains(option)
        return Button {
            onPick(option)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol(option))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isOn ? Color.white : Theme.accent)
                    .frame(width: 46, height: 46)
                    .background(isOn ? AnyShapeStyle(Theme.heroGradient) : AnyShapeStyle(Theme.accentSoft),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(option))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if !compact, let text = detail(option) {
                        Text(text).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if isOn && !compact {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                }
            }
            .padding(compact ? 12 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(isOn ? Theme.accent : Theme.line, lineWidth: isOn ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Shrinks a little while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Swiping on broad categories

private struct CategorySwipe: View {
    let categories: [Journey.Category]
    let plan: Journey.Plan
    @Binding var swipes: [String: Bool]
    let onDone: () -> Void

    @State private var drag: CGSize = .zero

    private var queue: [Journey.Category] {
        categories.filter { swipes[$0.id] == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SWIPE")
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)
                Text(plan == .dinner ? "What sounds good?" : "Which of these sound fun?")
                    .font(Theme.display(32))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Right for yes, left for no. Next you’ll see real places for every yes.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)

            ZStack {
                if !queue.isEmpty {
                    ForEach(Array(queue.prefix(3).enumerated().reversed()), id: \.element.id) { index, category in
                        card(category)
                            .scaleEffect(1 - CGFloat(index) * 0.05)
                            .offset(y: CGFloat(index) * 14)
                            .offset(index == 0 ? drag : .zero)
                            .rotationEffect(.degrees(index == 0 ? Double(drag.width / 18) : 0))
                            .allowsHitTesting(index == 0)
                            .gesture(dragGesture())
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Theme.accent)
                        Text("All swiped").font(Theme.display(24)).foregroundStyle(Theme.ink)
                    }
                    .onAppear(perform: finish)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)

            HStack(spacing: 28) {
                circleButton("xmark", tint: Vote.nope.color, label: "No") { decide(false) }
                Text("\(categories.count - queue.count + (queue.isEmpty ? 0 : 1)) of \(categories.count)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.muted)
                circleButton("heart.fill", tint: Vote.like.color, label: "Yes") { decide(true) }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)
            .disabled(queue.isEmpty)
        }
        .padding(.top, 12)
    }

    private func card(_ category: Journey.Category) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: category.symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white)
            Text(category.title)
                .font(Theme.display(34))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(category.blurb)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 420, maxHeight: 460)
        .background(
            LinearGradient(colors: [Theme.cardColor(category.id), Theme.cardColor(category.id).opacity(0.75)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topLeading) { stamp("YES", Vote.like.stampColor, show: drag.width > 40, angle: -12) }
        .overlay(alignment: .topTrailing) { stamp("NO", Vote.nope.stampColor, show: drag.width < -40, angle: 12) }
        .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Yes") { decide(true) }
        .accessibilityAction(named: "No") { decide(false) }
    }

    private func stamp(_ text: String, _ color: Color, show: Bool, angle: Double) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .black))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .rotationEffect(.degrees(angle))
            .padding(22)
            .opacity(show ? 1 : 0)
    }

    private func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 110 {
                    decide(value.translation.width > 0)
                } else {
                    withAnimation(.spring()) { drag = .zero }
                }
            }
    }

    private func decide(_ yes: Bool) {
        guard let top = queue.first else { return }
        withAnimation(.easeIn(duration: 0.2)) {
            drag = CGSize(width: yes ? 600 : -600, height: 40)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            swipes[top.id] = yes
            drag = .zero
        }
    }

    private func finish() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            onDone()
        }
    }

    private func circleButton(_ symbol: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 68, height: 68)
                .background(Theme.surface, in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - A place you can keep or drop

private struct PlaceRow: View {
    let place: Journey.Place
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                ZStack {
                    Theme.cardColor(place.id)
                    if let name = place.photoName, let photo = StarterPhoto.image(named: name) {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Text(CardText.initial(place.draft.title))
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.draft.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    Text(place.draft.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if place.source == .maps {
                        Label("Apple Maps", systemImage: "map")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isOn ? Theme.accent : Theme.line)
            }
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isOn ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isOn ? "In the deck. Tap to leave it out." : "Left out. Tap to add it back.")
    }
}

// MARK: - After the deck is made

/// Shown on top of the new deck: send it to your people, or start swiping.
struct JourneyMadeBanner: View {
    @Environment(Session.self) private var session
    let made: JourneyMade

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your plan is ready")
                        .font(Theme.display(20))
                        .foregroundStyle(.white)
                    Text("\(made.cards) places. Send it to your people so everyone can swipe.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                }
                Spacer(minLength: 0)
                Button {
                    session.journeyMade = nil
                } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                }
                .accessibilityLabel("Close")
            }
            HStack(spacing: 10) {
                Button {
                    session.journeyMade = nil
                    session.sheet = .qr(made.groupID)
                } label: {
                    Label("Send to your people", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.white, in: Capsule())
                }
                Button {
                    session.journeyMade = nil
                } label: {
                    Text("Start swiping")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                }
            }
        }
        .padding(16)
        .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.3), radius: 14, y: 6)
        .padding(.horizontal, 16)
    }
}
