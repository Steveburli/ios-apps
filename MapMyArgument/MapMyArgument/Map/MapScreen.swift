import SwiftUI
import Charts
import ArgumentKit

/// One argument: the tower, the stress tests, what to shore up, the claims, and sharing.
struct MapScreen: View {
    @Environment(Store.self) private var store
    let mapID: String

    @State private var scene = TowerScene()
    @State private var quake = 0
    @State private var gust = 0
    @State private var testing = false
    @State private var testNote: TestNote?
    @State private var dialogue: [Engine.Line] = []
    @State private var dialogueLabel = ""
    @State private var editing: EditTarget?
    @State private var confirmDelete = false
    @State private var replyText = ""
    @State private var replyError = ""
    @State private var copied = false

    struct TestNote: Equatable {
        let title: String
        let body: String
        let fell: Bool
        let toppled: Bool
    }

    struct EditTarget: Identifiable {
        let id: String
    }

    var map: ArgumentMap { store.map(mapID) ?? ArgumentMap(id: mapID) }
    var readOnly: Bool { store.isExample(mapID) }

    var body: some View {
        let map = self.map
        let evaluation = Engine.evaluate(map)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(map, evaluation)
                TowerView(map: map, evaluation: evaluation, scene: scene, quake: quake, gust: gust)
                testPanel(map)
                diagnostics(map, evaluation)
                outline(map, evaluation)
                knowledge(map)
                if readOnly {
                    exampleCompare
                } else {
                    share(map)
                    manage
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            ClaimEditor(map: store.binding(for: mapID), claimID: target.id, showsSurvey: true)
        }
        .onAppear(perform: runScreenshotTest)
    }

    // MARK: Header

    func header(_ map: ArgumentMap, _ e: Evaluation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(map.topic != map.thesis && !map.topic.isEmpty ? "Topic: " + map.topic : "Your argument")
            HStack(alignment: .top) {
                Text(map.thesis.isEmpty ? map.topic : map.thesis)
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Pill(map.stance.label.uppercased(), color: Theme.accent, background: Theme.accentSoft)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(map.claims.isEmpty ? "–" : e.score.percent)
                    .font(Theme.display(34))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.grade.label).font(.headline)
                    Text(e.grade.line).font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            Text("LEAN \(String(format: "%.1f", e.lean))° · LOAD \(e.weight)")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.muted)
            if readOnly {
                Notice(title: "This is the example map.",
                       text: "Try the stress tests, then make an editable copy to change it.")
                Button("Make an editable copy") {
                    let id = store.copyExample()
                    store.path.removeLast()
                    store.path.append(.map(id))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: Tests

    func testPanel(_ map: ArgumentMap) -> some View {
        Card {
            Text("Test it").font(.headline)
            HStack {
                Button("Gust of wind") { Task { await runWind() } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Earthquake") { Task { await runQuake() } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .disabled(testing || map.claims.isEmpty)
            Text("Send in an opponent").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Perspective.all) { p in
                        Button(p.label) { Task { await runCombat(p) } }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.line))
                            .foregroundStyle(Theme.ink)
                            .accessibilityHint(p.blurb)
                    }
                }
            }
            .disabled(testing || map.claims.isEmpty)
            if let note = testNote {
                Notice(title: note.title, text: note.body, tone: note.toppled ? .bad : note.fell ? .warn : .good)
                Button("Rebuild the tower") { reset() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            if !dialogue.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(dialogue.enumerated()), id: \.offset) { _, line in
                        if line.who == .them {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dialogueLabel.uppercased()).font(Theme.mono(10)).foregroundStyle(Theme.muted)
                                Text(line.text).font(.subheadline)
                            }
                            .padding(10)
                            .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(line.text).font(.subheadline.italic()).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
        }
    }

    func reset() {
        withAnimation(.easeInOut(duration: 0.4)) {
            scene = TowerScene()
            testNote = nil
            dialogue = []
            testing = false
        }
    }

    func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    func finish(title: String, map: ArgumentMap, fallen: [String], before: Double, after: Double, toppled: Bool, lean: Double) async {
        withAnimation(.easeIn(duration: 0.9)) { scene.fallen = fallen }
        await pause(0.9)
        withAnimation(.spring(duration: 0.9)) {
            scene.lean = lean
            scene.toppled = toppled
        }
        let labels = map.labels
        let names = fallen.compactMap { id in map.claims.first { $0.id == id }.map { "\(labels[id] ?? "") “\(Engine.short($0.text, 40))”" } }
        testNote = TestNote(
            title: toppled ? "\(title): it toppled" : "\(title): \(after.percent) stable (was \(before.percent))",
            body: names.isEmpty ? "Nothing fell." : "\(names.count == 1 ? "This fell" : "These fell"): \(names.joined(separator: "; ")).",
            fell: !names.isEmpty, toppled: toppled)
    }

    func runWind() async {
        let map = self.map
        reset()
        testing = true
        let outcome = Engine.wind(map)
        gust += 1
        withAnimation(.easeIn(duration: 1.1)) { scene.cloudsGone = Set(map.claims.filter(\.cloud).map(\.id)) }
        await pause(1.0)
        await finish(title: "After the wind", map: map, fallen: outcome.fallen, before: outcome.before, after: outcome.after,
                     toppled: outcome.toppled, lean: outcome.result.lean)
    }

    func runQuake() async {
        let map = self.map
        reset()
        testing = true
        let outcome = Engine.earthquake(map)
        quake += 1
        await pause(0.8)
        await finish(title: "After the earthquake", map: map, fallen: outcome.fallen, before: outcome.before, after: outcome.after,
                     toppled: outcome.toppled, lean: outcome.result.lean)
    }

    func runCombat(_ p: Perspective) async {
        let map = self.map
        reset()
        testing = true
        dialogueLabel = "The " + p.label
        let outcome = Engine.combat(map, p)
        let lines = Engine.lines(map, outcome)
        for phase in 0...3 {
            for line in lines where line.phase == phase {
                withAnimation { dialogue.append(line) }
                await pause(0.6)
            }
            switch phase {
            case 0:
                withAnimation(.easeIn(duration: 0.7)) {
                    scene.pulled = Set(outcome.sourcesOut.compactMap(\.source))
                    scene.cloudsGone = Set(outcome.cloudsOut)
                }
                await pause(0.7)
            case 1:
                withAnimation(.easeIn(duration: 0.8)) { scene.fallen = outcome.rejected }
                await pause(0.8)
            case 2:
                withAnimation { scene.pressed = true }
                await pause(0.5)
                withAnimation { scene.pressed = false }
                await finish(title: "After the \(p.label.lowercased())", map: map, fallen: outcome.rejected + outcome.attackFallen,
                             before: outcome.before, after: outcome.after, toppled: outcome.toppled, lean: outcome.result.lean)
            default:
                break
            }
        }
    }

    /// The cloud build's "test" and "combat" screenshots show a stress test that has already run.
    func runScreenshotTest() {
        switch Screenshots.screen {
        case "test": Task { await runQuake() }
        case "combat": Task { await runCombat(Perspective.find("progressive")!) }
        default: break
        }
    }

    // MARK: Diagnostics

    func diagnostics(_ map: ArgumentMap, _ e: Evaluation) -> some View {
        let labels = map.labels
        let byID = Dictionary(map.claims.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func list(_ ids: [String]) -> String {
            ids.map { "\(labels[$0] ?? "?")  \(Engine.short(byID[$0]?.text ?? "", 70))" }.joined(separator: "\n")
        }
        let f = e.flags
        return VStack(alignment: .leading, spacing: 10) {
            Text("What to shore up").font(Theme.display(20))
            if map.claims.isEmpty {
                Notice(title: "Nothing here yet", text: "Add your first reason to raise a pillar.")
            }
            if !f.termites.isEmpty {
                Notice(title: "Termites", text: "You're very sure of these but said you haven't looked into them much. They're hollow until you do.",
                       detail: list(f.termites), tone: .bad)
            }
            if !f.unsupported.isEmpty {
                Notice(title: "Nothing underneath", text: "No sources you trust, no supporting points, no belief cloud. These are floating.",
                       detail: list(f.unsupported), tone: .warn)
            }
            if f.headInClouds {
                Notice(title: "Head in the clouds", text: "\(f.clouds) of your claims rest on belief alone. That's a lot of sky for one building.", tone: .warn)
            }
            if f.cherryPicking {
                Notice(title: "Only good news?", text: "You haven't written down a single point against your own argument. If you only collect facts that agree with you, the tower looks sturdier than it is.", tone: .warn)
            }
            if f.unansweredCounters > 0 {
                Notice(title: "\(f.unansweredCounters) unanswered counter-argument\(f.unansweredCounters == 1 ? "" : "s")",
                       text: "Each one leans on its pillar until you have an answer.")
            }
            if !f.humble.isEmpty {
                Notice(title: "You know more than you're claiming", text: list(f.humble), tone: .good)
            }
            if !map.claims.isEmpty && f.termites.isEmpty && f.unsupported.isEmpty && !f.headInClouds && !f.cherryPicking && f.unansweredCounters == 0 {
                Notice(title: "No obvious weak spots.", text: "Try an opponent to see it from the other side.", tone: .good)
            }
        }
    }

    // MARK: Outline

    func outline(_ map: ArgumentMap, _ e: Evaluation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("The structure").font(Theme.display(20))
                Spacer()
                if !readOnly {
                    Button("Add a reason") {
                        let claim = Claim()
                        var copy = map
                        copy.claims.append(claim)
                        store.upsert(copy)
                        editing = EditTarget(id: claim.id)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            ForEach(map.outline) { item in
                ClaimCard(map: map, claim: item.claim, label: item.label, depth: item.depth, result: e.claims[item.claim.id])
                    .contentShape(Rectangle())
                    .onTapGesture { if !readOnly { editing = EditTarget(id: item.claim.id) } }
                    .contextMenu {
                        if !readOnly {
                            Button("Edit") { editing = EditTarget(id: item.claim.id) }
                            if item.depth < 2 {
                                Button("Add a supporting point") {
                                    let claim = Claim(parent: item.claim.id)
                                    var copy = map
                                    copy.claims.append(claim)
                                    store.upsert(copy)
                                    editing = EditTarget(id: claim.id)
                                }
                            }
                            Button("Remove", role: .destructive) {
                                var copy = map
                                copy.removeClaim(item.claim.id)
                                store.upsert(copy)
                            }
                        }
                    }
            }
            if !readOnly && !map.claims.isEmpty {
                Text("Tap a claim to edit it. Touch and hold for more.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: Knowledge

    func knowledge(_ map: ArgumentMap) -> some View {
        let labels = map.labels
        let points = Engine.knowledge(map)
        return Card {
            Text("What you know against how sure you are").font(.headline)
            Text("Top left is the termite zone: very sure, little research. Bottom right is humble: you know more than you're claiming.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Chart {
                RectangleMark(xStart: .value("Familiarity", 0.6), xEnd: .value("Familiarity", 2.5),
                              yStart: .value("Confidence", 70), yEnd: .value("Confidence", 100))
                    .foregroundStyle(Theme.failingSoft)
                RectangleMark(xStart: .value("Familiarity", 3.5), xEnd: .value("Familiarity", 5.4),
                              yStart: .value("Confidence", 0), yEnd: .value("Confidence", 35))
                    .foregroundStyle(Theme.solidSoft)
                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                    PointMark(x: .value("Familiarity", Double(p.familiarity) + Double(i % 3 - 1) * 0.08),
                              y: .value("Confidence", p.confidence))
                        .symbolSize(260)
                        .foregroundStyle(p.verdict == .termites ? Theme.failing : p.verdict == .humble ? Theme.solid : Theme.ink)
                        .annotation(position: .overlay) {
                            Text(labels[p.id] ?? "")
                                .font(Theme.mono(8, weight: .bold))
                                .foregroundStyle(Theme.bg)
                        }
                }
            }
            .chartXScale(domain: 0.6...5.4)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [1.0, 2.0, 3.0, 4.0, 5.0]) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .chartXAxisLabel("how much you know →")
            .chartYAxisLabel("how sure you are →")
            .frame(height: 220)
        }
    }

    // MARK: Sharing

    var exampleCompare: some View {
        Card {
            Text("See a comparison").font(.headline)
            Text("Sam rated this example map. See where they agree and where the conversation should start.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Button("Compare with Sam") {
                store.comparison = Comparison(mine: Catalog.example, theirs: Catalog.exampleFriend, meLabel: "Example")
                store.path.append(.compare)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    func share(_ map: ArgumentMap) -> some View {
        @Bindable var store = store
        let code = store.shareCode(for: map)
        return Card {
            Text("Send it to a friend").font(.headline)
            Text("They paste the code into Map My Argument, on the web or the iPhone app, rate each of your claims, and send theirs back. Then you'll see exactly where you agree.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            TextField("Your name, so they know who it's from", text: $store.name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.save() }
            ShareLink(item: "Here's my argument on Map My Argument. Paste this code into the app to rate it:\n\n\(code)") {
                Label("Share the code", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())
            Button(copied ? "Copied" : "Copy the code") {
                UIPasteboard.general.string = code
                copied = true
            }
            .buttonStyle(SecondaryButtonStyle())
            Divider()
            Text("Got their answer?").font(.subheadline.weight(.semibold))
            HStack {
                PasteButton(payloadType: String.self) { strings in
                    replyText = strings.first ?? ""
                    openReply(map)
                }
                .labelStyle(.titleAndIcon)
                TextField("Or type it here", text: $replyText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { openReply(map) }
            }
            if !replyError.isEmpty {
                Notice(title: "Couldn't open that", text: replyError, tone: .bad)
            }
        }
    }

    func openReply(_ map: ArgumentMap) {
        do {
            let reply = try ShareCode.decode(replyText)
            if reply.basedOn != map.id && Compare.run(map, reply).items.isEmpty {
                replyError = "That code doesn't seem to be about this map. Ask them to rate this map's code first."
                return
            }
            replyError = ""
            store.comparison = Comparison(mine: map, theirs: reply, canAdopt: true)
            store.path.append(.compare)
        } catch {
            replyError = error.localizedDescription
        }
    }

    var manage: some View {
        Card {
            Text("This map").font(.headline)
            Button("Change the position or sources") {
                store.editPosition(of: mapID)
                store.path.append(.build)
            }
            .buttonStyle(SecondaryButtonStyle())
            Button("Delete this map", role: .destructive) { confirmDelete = true }
                .frame(maxWidth: .infinity)
                .confirmationDialog("Delete this map for good?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        store.delete(mapID)
                        if !store.path.isEmpty { store.path.removeLast() }
                    }
                }
        }
    }
}

/// One claim in the outline.
struct ClaimCard: View {
    let map: ArgumentMap
    let claim: Claim
    let label: String
    let depth: Int
    let result: ClaimResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(label)
                    .font(Theme.mono(12, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 6))
                Text(claim.text.isEmpty ? "(no words yet)" : claim.text)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let result { Pill(status: result.status) }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.sunk)
                    Capsule().fill(Theme.color(result?.status ?? .failing))
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, result?.stability ?? 0))))
                }
            }
            .frame(height: 6)
            .accessibilityLabel("Stability \((result?.stability ?? 0).percent)")
            FlowText(parts: meta)
            ForEach(claim.sources) { source in
                let distrusted = map.trust(source.kind) == .distrust
                Text("• \(source.title.isEmpty ? "Untitled source" : source.title) · \(source.kind.label.lowercased())\(source.lean == .neutral ? "" : ", \(source.lean.rawValue)-leaning")\(distrusted ? " · you don't trust these" : "")")
                    .font(.footnote)
                    .strikethrough(distrusted)
                    .foregroundStyle(distrusted ? Theme.muted : Theme.ink)
            }
            ForEach(claim.counters.filter { !$0.text.isEmpty }) { counter in
                Text("\(counter.answered ? "Answered" : "Against"): \(counter.text) (\(counter.strength)/5)")
                    .font(.footnote)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
        .padding(.leading, CGFloat(depth) * 18)
    }

    var meta: [String] {
        var parts = [result?.tier.isEmpty == false ? result!.tier : "no sources",
                     "weight \(claim.importance)/5", "\(claim.confidence)% sure", Familiarity.label(claim.familiarity)]
        if result?.termites == true { parts.append("termites") }
        if claim.cloud { parts.append("belief cloud") }
        if claim.votes > 0 { parts.append("\(claim.votes) agree") }
        return parts
    }
}

/// Small grey facts separated by dots, wrapping as needed.
struct FlowText: View {
    let parts: [String]

    var body: some View {
        Text(parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(Theme.muted)
    }
}
