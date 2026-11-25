import SwiftUI
import ArgumentKit

/// The survey that builds a map, one step at a time: topic, which sources you trust,
/// your position, your reasons, what holds each up, how familiar you are with each,
/// and how sure. Then "Construct my argument".
struct BuildFlow: View {
    @Environment(Store.self) private var store
    @State private var editing: ClaimTarget?
    @FocusState private var focused: String?

    struct ClaimTarget: Identifiable { let id: String }

    static let steps = ["Topic", "Sources", "Position", "Reasons", "Support", "Familiarity", "Confidence"]

    var draft: Binding<ArgumentMap> { store.draftBinding }
    var step: Int { min(store.draftStep, Self.steps.count - 1) }

    var canGoOn: Bool {
        let d = draft.wrappedValue
        switch step {
        case 0: return !d.topic.trimmingCharacters(in: .whitespaces).isEmpty
        case 2: return !d.thesis.trimmingCharacters(in: .whitespaces).isEmpty
        case 3: return d.roots.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        default: return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progress
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 0: topicStep
                    case 1: trustStep
                    case 2: positionStep
                    case 3: reasonsStep
                    case 4: supportStep
                    case 5: familiarityStep
                    default: confidenceStep
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .background(Theme.bg)
        .navigationTitle(Self.steps[step])
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if store.draft == nil { store.startDraft() } }
        .sheet(item: $editing) { target in
            ClaimEditor(map: draft, claimID: target.id)
        }
    }

    var progress: some View {
        HStack(spacing: 4) {
            ForEach(0..<Self.steps.count, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Theme.accent : Theme.line)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(Self.steps.count)")
    }

    var bottomBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { go(step - 1) }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 120)
            }
            if step < Self.steps.count - 1 {
                Button("Next") { next() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canGoOn)
                    .opacity(canGoOn ? 1 : 0.5)
            } else {
                Button("Construct my argument") {
                    if let id = store.construct() {
                        store.path = [.map(id)]
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(16)
        .background(Theme.surface.shadow(.drop(color: .black.opacity(0.06), radius: 8, y: -2)))
    }

    func go(_ newStep: Int) {
        focused = nil
        withAnimation(.easeInOut(duration: 0.2)) { store.draftStep = max(0, newStep) }
        store.save()
    }

    func next() {
        if step == 3 || step == 4 {
            draft.wrappedValue.claims.removeAll { $0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.sources.isEmpty }
        }
        go(step + 1)
    }

    func heading(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Step \(step + 1) of \(Self.steps.count)")
            Text(title).font(Theme.display(24)).fixedSize(horizontal: false, vertical: true)
            if !text.isEmpty {
                Text(text).font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Steps

    var topicStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("What do you want to argue about?", "")
            ForEach(Catalog.topics) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(group.category)
                    FlowLayout(spacing: 8) {
                        ForEach(group.items, id: \.self) { topic in
                            Chip(text: topic, selected: draft.wrappedValue.topic == topic) { pick(topic) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Or write your own").font(.subheadline.weight(.semibold))
                TextField("A statement someone could agree or disagree with", text: Binding(
                    get: {
                        let t = draft.wrappedValue.topic
                        return Catalog.topics.contains { $0.items.contains(t) } ? "" : t
                    },
                    set: { pick($0) }), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: "topic")
            }
        }
    }

    func pick(_ topic: String) {
        var d = draft.wrappedValue
        if d.thesis.trimmingCharacters(in: .whitespaces).isEmpty || d.thesis == d.topic { d.thesis = topic }
        d.topic = topic
        draft.wrappedValue = d
    }

    var trustStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("Which sources do you trust?",
                    "Your answers decide how much each source holds up. A source you don't trust holds up nothing, even if it agrees with you.")
            ForEach(SourceKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.label).font(.subheadline.weight(.semibold))
                    Picker(kind.label, selection: Binding(
                        get: { draft.wrappedValue.trust(kind) },
                        set: { value in
                            draft.wrappedValue.trust[kind.rawValue] = value
                            store.trust[kind.rawValue] = value
                            store.save()
                        })) {
                        ForEach(Trust.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
        }
    }

    var positionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Where do you stand?", "Topic: “\(draft.wrappedValue.topic)”")
            Picker("Stance", selection: draft.stance) {
                ForEach(Stance.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your position, in one sentence").font(.subheadline.weight(.semibold))
                TextField("Say it the way you'd say it to a friend", text: draft.thesis, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: "thesis")
                Text("This is the roof of your tower. Everything else has to hold it up.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    var reasonsStep: some View {
        let roots = draft.wrappedValue.roots
        return VStack(alignment: .leading, spacing: 14) {
            heading("Why do you think so?",
                    "List the reasons your position rests on, and how much it depends on each. Facts first: there's no point arguing whether something is good until you agree it exists.")
            ForEach(Array(roots.enumerated()), id: \.element.id) { i, claim in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text("\(i + 1)")
                            .font(Theme.mono(13, weight: .bold))
                            .foregroundStyle(Theme.bg)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 6))
                        TextField("Because…", text: draft.claim(claim.id).text, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .focused($focused, equals: claim.id)
                    }
                    Text("How much does your position depend on this?").font(.footnote).foregroundStyle(Theme.muted)
                    Picker("Importance", selection: draft.claim(claim.id).importance) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text(Importance.label(claim.importance)).font(.footnote).foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Remove", role: .destructive) { draft.wrappedValue.removeClaim(claim.id) }
                            .font(.footnote)
                    }
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
            }
            Button {
                let claim = Claim()
                draft.wrappedValue.claims.append(claim)
                focused = claim.id
            } label: {
                Label("Add a reason", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            Text(roots.isEmpty ? "Start with your strongest one." : "\(roots.count) so far. Most strong arguments have three to five.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    var supportStep: some View {
        let map = draft.wrappedValue
        let evaluation = Engine.evaluate(map)
        return VStack(alignment: .leading, spacing: 14) {
            heading("What holds each reason up?",
                    "Add your sources, the points underneath, and the best argument against each one. Be honest: a belief cloud is allowed, it just doesn't hold much.")
            TowerView(map: map, evaluation: evaluation)
            ForEach(map.outline) { item in
                Button { editing = ClaimTarget(id: item.claim.id) } label: {
                    ClaimCard(map: map, claim: item.claim, label: item.label, depth: item.depth, result: evaluation.claims[item.claim.id])
                }
                .buttonStyle(.plain)
            }
            Text("Tap a reason to add its sources and supporting points.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    var familiarityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("How familiar are you with each of these?", "Not whether it's true, just how much you've looked into it.")
            ForEach(draft.wrappedValue.outline) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(item.label)  \(item.claim.text)").font(.body.weight(.semibold))
                    FamiliarityPicker(value: draft.claim(item.claim.id).familiarity)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    var confidenceStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading("How sure are you that each is true?",
                    "0% is “probably not”, 100% is “certain”. Opponents push hardest on what you're unsure of.")
            ForEach(draft.wrappedValue.outline) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(item.label)  \(item.claim.text)").font(.body.weight(.semibold))
                    ConfidenceSlider(value: draft.claim(item.claim.id).confidence)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}

/// A rounded, tappable label.
struct Chip: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(Theme.ink)
                .background(selected ? Theme.accentSoft : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.accent : Theme.line))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays out children left to right, wrapping onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, widest), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
