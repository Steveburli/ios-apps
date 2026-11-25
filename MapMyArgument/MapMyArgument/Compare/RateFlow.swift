import SwiftUI
import ArgumentKit

/// Rating a friend's map: which sources you trust, how sure you are of each of their
/// claims, and any reasons of your own. Then the comparison, with a code to send back.
struct RateFlow: View {
    @Environment(Store.self) private var store
    @State private var step = 0

    var rating: Binding<ArgumentMap> {
        Binding(
            get: { store.rating?.mine ?? ArgumentMap() },
            set: { store.rating?.mine = $0 })
    }

    var body: some View {
        if let theirs = store.rating?.theirs {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Eyebrow("Rating \(theirs.author.isEmpty ? "a friend" : theirs.author)'s argument")
                        Text("“\(theirs.thesis.isEmpty ? theirs.topic : theirs.thesis)”")
                            .font(Theme.display(22))
                            .fixedSize(horizontal: false, vertical: true)
                        switch step {
                        case 0: trust
                        case 1: claims(theirs)
                        default: own(theirs)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Back") { withAnimation { step -= 1 } }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(maxWidth: 120)
                    }
                    if step < 2 {
                        Button(step == 0 ? "Rate their claims" : "Next") { withAnimation { step += 1 } }
                            .buttonStyle(PrimaryButtonStyle())
                    } else {
                        Button("See where we agree") {
                            store.finishRating()
                            store.path = [.compare]
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(16)
                .background(Theme.surface)
            }
            .background(Theme.bg)
            .navigationTitle("Rate")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Nothing to rate", systemImage: "building.columns",
                                   description: Text("Paste a friend's code on the home screen."))
        }
    }

    var trust: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("First, which sources do you trust? They'll see where your trust differs.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            ForEach(SourceKind.allCases) { kind in
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.label).font(.subheadline.weight(.semibold))
                    Picker(kind.label, selection: Binding(
                        get: { rating.wrappedValue.trust(kind) },
                        set: { value in
                            rating.wrappedValue.trust[kind.rawValue] = value
                            store.trust[kind.rawValue] = value
                            store.save()
                        })) {
                        ForEach(Trust.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            Text("Where do you stand on the topic?").font(.subheadline.weight(.semibold))
            Picker("Stance", selection: rating.stance) {
                ForEach(Stance.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    func claims(_ theirs: ArgumentMap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("For each claim: how sure are you it's true, and how much do you know about it?")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            ForEach(theirs.outline) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(item.label)  \(item.claim.text)").font(.body.weight(.semibold))
                    if !item.claim.sources.isEmpty {
                        Text("Their sources: " + item.claim.sources.map { $0.title.isEmpty ? $0.kind.label : $0.title }.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    ConfidenceSlider(value: rating.claim(item.claim.id).confidence)
                    FamiliarityPicker(value: rating.claim(item.claim.id).familiarity)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    func own(_ theirs: ArgumentMap) -> some View {
        let theirIDs = Set(theirs.claims.map(\.id))
        let mine = rating.wrappedValue.claims.filter { !theirIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Anything they left out? Add your own reasons (optional).")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            ForEach(mine) { claim in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Because…", text: rating.claim(claim.id).text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    ConfidenceSlider(value: rating.claim(claim.id).confidence)
                    Button("Remove", role: .destructive) { rating.wrappedValue.removeClaim(claim.id) }
                        .font(.footnote)
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            }
            Button {
                rating.wrappedValue.claims.append(Claim(confidence: 70))
            } label: {
                Label("Add a reason of my own", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
