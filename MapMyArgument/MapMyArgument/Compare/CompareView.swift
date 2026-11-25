import SwiftUI
import ArgumentKit

/// Two maps side by side: what you agree on, where to start talking (foundations first),
/// where your trust in sources differs, and what only one of you said.
struct CompareView: View {
    @Environment(Store.self) private var store
    @State private var index = 0
    @State private var counted: Int?
    @State private var copied = false

    var body: some View {
        if let cmp = store.comparison {
            content(cmp)
        } else {
            ContentUnavailableView("Nothing to compare", systemImage: "rectangle.split.2x1",
                                   description: Text("Paste a friend's answer under your map's “Send it to a friend”."))
        }
    }

    func content(_ cmp: Comparison) -> some View {
        let result = Compare.run(cmp.mine, cmp.theirs)
        let me = cmp.meLabel
        let them = cmp.theirs.author.isEmpty ? "Your friend" : cmp.theirs.author
        let labels = cmp.mine.labels
        let mineByID = Dictionary(cmp.mine.claims.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let theirsByID = Dictionary(cmp.theirs.claims.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Comparison")
                    Text("\(me) and \(them)").font(Theme.display(28))
                    Text("“\(cmp.mine.thesis.isEmpty ? cmp.mine.topic : cmp.mine.thesis)”. \(me) \(me == "You" ? "are" : "is") \(stanceWord(cmp.mine.stance)); \(them) is \(stanceWord(cmp.theirs.stance)).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    stat(result.agreeCount, "claims you agree on")
                    stat(result.disagreeCount, "one of you thinks is false")
                    stat(result.degreeCount, "agree, but not how sure")
                    stat(result.onlyTheirs.count, "reasons only \(them) gave")
                }

                if result.queue.isEmpty {
                    Notice(title: "Nothing to argue about here.", text: "You agree on every claim you share.", tone: .good)
                } else {
                    let i = min(index, result.queue.count - 1)
                    let item = result.queue[i]
                    Card {
                        Eyebrow("Talk it through · \(i + 1) of \(result.queue.count)\(item.depth > 0 ? " · a foundation" : "")")
                        Text("\(labels[item.mine] ?? "")  \(item.text)").font(Theme.display(19))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 10) {
                            side(me, item.myConfidence, mineByID[item.mine])
                            side(them, item.theirConfidence, theirsByID[item.theirs])
                        }
                        Text(prompt(item.kind)).font(.subheadline)
                        ForEach(Array(item.conflicts.enumerated()), id: \.offset) { _, conflict in
                            Notice(title: "Different trust",
                                   text: "\(conflict.side == .mine ? them + " doesn't" : me + (me == "You" ? " don't" : " doesn't")) trust \(conflict.kind.label.lowercased())s, and this rests on one. Is there a source you both trust?",
                                   tone: .warn)
                        }
                        if result.queue.count > 1 {
                            HStack {
                                Button("Previous") { index = max(0, i - 1) }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .disabled(i == 0)
                                Button("Next") { index = i + 1 }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(i >= result.queue.count - 1)
                                    .opacity(i >= result.queue.count - 1 ? 0.5 : 1)
                            }
                        }
                    }
                }

                Card {
                    Text("Claim by claim").font(.headline)
                    ForEach(result.items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(labels[item.mine] ?? "").font(Theme.mono(12, weight: .bold)).frame(width: 26, alignment: .leading)
                            Text(Engine.short(item.text, 90)).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(item.myConfidence)% · \(item.theirConfidence)%").font(Theme.mono(12))
                                kindPill(item.kind)
                            }
                        }
                        Divider()
                    }
                    Text("\(me) · \(them)").font(.caption).foregroundStyle(Theme.muted)
                }

                if !result.onlyTheirs.isEmpty {
                    Card {
                        Text("Reasons only \(them) gave").font(.headline)
                        ForEach(result.onlyTheirs, id: \.self) { id in
                            HStack {
                                Text(theirsByID[id]?.text ?? "").font(.subheadline)
                                Spacer()
                                if cmp.canAdopt {
                                    Button("Add to my map") { store.adopt(id) }.font(.footnote.weight(.semibold))
                                }
                            }
                        }
                    }
                }
                if !result.onlyMine.isEmpty {
                    Card {
                        Text(me == "You" ? "Reasons only you gave" : "Reasons only \(me) gave").font(.headline)
                        ForEach(result.onlyMine, id: \.self) { id in
                            Text(mineByID[id]?.text ?? "").font(.subheadline)
                        }
                    }
                }
                if !result.trustSplit.isEmpty {
                    Card {
                        Text("Where your trust in sources differs").font(.headline)
                        ForEach(result.trustSplit, id: \.kind) { split in
                            HStack {
                                Text(split.kind.label).font(.subheadline)
                                Spacer()
                                Text("\(split.mine.label) · \(split.theirs.label)").font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                        Text("\(me) · \(them)").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                if cmp.canAdopt {
                    Card {
                        Text("Count their agreement").font(.headline)
                        Text("Each claim \(them) agrees with gets one more vote, which makes it a little broader and steadier.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        let already = cmp.mine.counted.contains(cmp.theirs.id)
                        Button(already ? (counted.map { "\($0) claims got a vote" } ?? "Already counted") : "Count it") {
                            counted = store.countVotes()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(already)
                    }
                }
                if !cmp.replyCode.isEmpty {
                    Card {
                        Text("Send your answers back").font(.headline)
                        Text("Give this code to \(them == "Your friend" ? "them" : them) so they can see the comparison too.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        ShareLink(item: "Here are my answers to your argument on Map My Argument. Paste this code under your map:\n\n\(cmp.replyCode)") {
                            Label("Share my answers", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button(copied ? "Copied" : "Copy the code") {
                            UIPasteboard.general.string = cmp.replyCode
                            copied = true
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
    }

    func stanceWord(_ s: Stance) -> String {
        switch s {
        case .for: return "for"
        case .against: return "against"
        case .unsure: return "not sure"
        }
    }

    func stat(_ n: Int, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(n)").font(Theme.display(28)).monospacedDigit()
            Text(text).font(.footnote).foregroundStyle(Theme.ink)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
    }

    func side(_ who: String, _ confidence: Int, _ claim: Claim?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(who).font(.footnote).foregroundStyle(Theme.muted)
            Text("\(confidence)% sure").font(Theme.mono(18, weight: .bold))
            let sources = claim?.sources ?? []
            Text(sources.isEmpty ? "No sources given" : sources.map { $0.title.isEmpty ? $0.kind.label : $0.title }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.sunk, in: RoundedRectangle(cornerRadius: 10))
    }

    func prompt(_ kind: Compare.Kind) -> String {
        switch kind {
        case .disagree: return "One of you thinks this is true and the other doesn't. Put your sources side by side and settle the facts before arguing about what follows from them."
        case .degree: return "You agree it's true, but not how sure to be. What would it take to move either of you?"
        case .bothDoubt: return "Neither of you is convinced. Is it worth keeping in the argument at all?"
        case .agree: return "You agree on this. Can you agree on a source for it, too?"
        }
    }

    func kindPill(_ kind: Compare.Kind) -> Pill {
        switch kind {
        case .agree: return Pill("AGREE", color: Theme.solid, background: Theme.solidSoft)
        case .bothDoubt: return Pill("BOTH DOUBT", color: Theme.muted, background: Theme.sunk)
        case .degree: return Pill("HOW SURE", color: Theme.strained, background: Theme.strainedSoft)
        case .disagree: return Pill("DISAGREE", color: Theme.failing, background: Theme.failingSoft)
        }
    }
}

/// How the tower is scored, in plain words.
struct HowView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("The rules")
                Text("How the tower is scored").font(Theme.display(26))
                Text("Every number comes from what you entered. Nothing is judged by what you believe, only by how well it's held up.")
                section("Strength of a claim", [
                    "Sources: one counts as 45% (I), two as 75% (II), three or more independent ones as 100% (IXI). A source you don't trust counts for nothing, one you're unsure of counts 70% as much, and two with the same title count once.",
                    "Supporting points: each passes up half of its own strength, scaled by how much the point above depends on it.",
                    "A belief cloud adds 35%.",
                    "People who agree add up to 15%. Each unanswered counter-argument takes away 5% per point of its strength (1 to 5); an answered one takes 1%.",
                    "Then your conviction counts: the total is multiplied by 0.6 plus 0.4 × how sure you are. If you're 70% sure or more but rated your familiarity 2 or less, termites eat 30% of it.",
                ])
                section("Weight to carry", [
                    "A claim your position leans on heavily has more to hold up: 0.2 + 0.14 × its importance (1 to 5).",
                    "Stability is strength divided by that weight. At 100% or more it's solid, from 60% strained, from 35% sagging, and below that it's failing: in any stress test it falls.",
                ])
                section("The whole tower", [
                    "The score is the average stability of your top-level reasons (capped at 100% each), weighted by importance. 85% and up is a fortress, 65% solid, 45% leaning, 25% sagging, and below 25% it topples.",
                    "The tower leans toward whichever half has the weaker pillars.",
                ])
                section("Stress tests", [
                    "Wind blows every belief cloud away.",
                    "An earthquake shakes everything to 80% of its strength and collapses anything with termites.",
                    "An opponent throws out the sources it doesn't trust, knocks out the premises you said it would reject, then pushes on every claim you're less than 50% sure of (down to 75%).",
                ])
                section("Comparing", [
                    "A friend's rating keeps your claims, so they line up exactly. Maps built separately are matched by wording.",
                    "The conversation starts at the foundations: there's no point arguing whether something is good until you agree it exists.",
                ])
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.bg)
        .navigationTitle("Scoring")
        .navigationBarTitleDisplayMode(.inline)
    }

    func section(_ title: String, _ points: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.bold))
            ForEach(points, id: \.self) { point in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(point).fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
            }
        }
    }
}
