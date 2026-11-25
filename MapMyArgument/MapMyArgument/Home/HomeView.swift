import SwiftUI
import ArgumentKit

struct HomeView: View {
    @Environment(Store.self) private var store
    @State private var code = ""
    @State private var codeError = ""
    @State private var exampleScene = TowerScene()
    @State private var quake = 0
    @State private var gust = 0
    @State private var demoRan = false

    var body: some View {
        let example = Catalog.example
        let evaluation = Engine.evaluate(example)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Eyebrow("Argument mapping")
                    Text("See if your argument can stand.")
                        .font(Theme.display(34, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Build your position like a building. Every reason is a pillar, every source is a support, and anything you only believe floats on a cloud. Then send in a gust of wind, an earthquake or someone who disagrees, and watch what stays standing.")
                        .font(.body)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button { store.path.append(.map(example.id)) } label: {
                        TowerView(map: example, evaluation: evaluation, scene: exampleScene, quake: quake, gust: gust)
                    }
                    .buttonStyle(.plain)
                    Text("Example: “\(example.thesis)”. \(evaluation.score.percent) stable, \(evaluation.grade.label.lowercased()). Pillar 3 rests on a social media post its owner doesn't trust, and pillar 4 floats on a belief cloud.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    HStack {
                        Button("Wind") { demo(Engine.wind(example), wind: true) }
                        Button("Earthquake") { demo(Engine.earthquake(example), wind: false) }
                        Button("Rebuild") {
                            withAnimation { exampleScene = TowerScene() }
                            demoRan = false
                        }
                        .disabled(!demoRan)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                VStack(spacing: 10) {
                    Button("Build my argument") {
                        if store.draft == nil { store.startDraft() }
                        store.path.append(.build)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Explore the example") { store.path.append(.map(example.id)) }
                        .buttonStyle(SecondaryButtonStyle())
                    if let draft = store.draft, !draft.topic.isEmpty {
                        Button("Finish “\(Engine.short(draft.topic, 40))”") { store.path.append(.build) }
                            .font(.subheadline.weight(.semibold))
                    }
                }

                if !store.maps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your maps").font(Theme.display(20))
                        ForEach(store.maps) { map in
                            Button { store.path.append(.map(map.id)) } label: { MapRow(map: map, me: store.name) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                Card {
                    Text("Got a code from a friend?").font(.headline)
                    Text("If it's their map, you'll rate it. If it's their answer to yours, you'll see where you agree.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            code = strings.first ?? ""
                            open()
                        }
                        TextField("MMA1.…", text: $code)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(open)
                    }
                    if !codeError.isEmpty {
                        Notice(title: "Couldn't open that", text: codeError, tone: .bad)
                    }
                    Button("See an example comparison") {
                        store.comparison = Comparison(mine: Catalog.example, theirs: Catalog.exampleFriend, meLabel: "Example")
                        store.path.append(.compare)
                    }
                    .font(.subheadline.weight(.semibold))
                }

                Legend()
            }
            .padding(16)
        }
        .background(Theme.bg)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    BrandMark().frame(width: 24, height: 24)
                    Text("Map My Argument").font(.system(size: 16, weight: .heavy).width(.expanded))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.path.append(.how) } label: {
                    Label("How scoring works", systemImage: "info.circle")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    func demo(_ outcome: Engine.TestOutcome, wind: Bool) {
        withAnimation { exampleScene = TowerScene() }
        demoRan = true
        if wind {
            gust += 1
            withAnimation(.easeIn(duration: 1.1)) {
                exampleScene.cloudsGone = Set(Catalog.example.claims.filter(\.cloud).map(\.id))
            }
        } else {
            quake += 1
        }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeIn(duration: 0.9)) { exampleScene.fallen = outcome.fallen }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.spring(duration: 0.9)) {
                exampleScene.lean = outcome.result.lean
                exampleScene.toppled = outcome.toppled
            }
        }
    }

    func open() {
        do {
            switch try store.receive(code) {
            case .rate: store.path.append(.rate)
            case .compare: store.path.append(.compare)
            case .alreadyHave(let id): store.path.append(.map(id))
            }
            code = ""
            codeError = ""
        } catch {
            codeError = error.localizedDescription
        }
    }
}

struct MapRow: View {
    let map: ArgumentMap
    let me: String

    var body: some View {
        let e = Engine.evaluate(map)
        HStack(spacing: 12) {
            TowerView(map: map, evaluation: e, compact: true)
                .frame(width: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(map.thesis.isEmpty ? (map.topic.isEmpty ? "Untitled" : map.topic) : map.thesis)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Text(subtitle(e))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
    }

    func subtitle(_ e: Evaluation) -> String {
        var parts = [map.claims.isEmpty ? "No reasons yet" : "\(e.score.percent) · \(e.grade.label)"]
        if !map.basedOn.isEmpty { parts.append("rating") }
        if !map.author.isEmpty && map.author != me { parts.append(map.author) }
        return parts.joined(separator: " · ")
    }
}

/// How to read a tower.
struct Legend: View {
    var body: some View {
        Card {
            Text("How to read a tower").font(.headline)
            row("rectangle.portrait", "Pillars", "are your reasons. Wider means better supported; the beam sags over weak ones.")
            row("chart.bar", "Posts", "are sources. One is weak (I), two moderate (II), three independent ones are braced (IXI).")
            row("cloud", "Belief clouds", "hold up what you believe without evidence. Too many and your head is in the clouds.")
            row("ant", "Termites", "eat claims you're very sure of but haven't looked into.")
            row("arrow.left", "Red arrows", "are counter-arguments you haven't answered yet.")
            row("house", "The roof", "is your conclusion. Its load is how much weight your reasons carry.")
        }
    }

    func row(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(Theme.accent)
            Text("\(Text(title).bold()) \(text)")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
