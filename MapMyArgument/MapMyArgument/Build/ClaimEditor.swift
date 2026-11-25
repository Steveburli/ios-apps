import SwiftUI
import ArgumentKit

/// Edits one claim: its words, weight, sources, supporting points, belief cloud,
/// strongest counter-argument and who would reject it. Supporting points open in the
/// same sheet, one level deeper.
struct ClaimEditor: View {
    @Binding var map: ArgumentMap
    let claimID: String
    /// Also ask how familiar and how sure (on the map screen; the builder asks these in its own steps).
    var showsSurvey = false
    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            ClaimForm(map: $map, claimID: claimID, showsSurvey: showsSurvey, path: $path)
                .navigationDestination(for: String.self) { id in
                    ClaimForm(map: $map, claimID: id, showsSurvey: showsSurvey, path: $path)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct ClaimForm: View {
    @Binding var map: ArgumentMap
    let claimID: String
    let showsSurvey: Bool
    @Binding var path: [String]
    @Environment(\.dismiss) private var dismiss

    var claim: Binding<Claim> { $map.claim(claimID) }
    var isSub: Bool { claim.wrappedValue.parent != nil }

    var counterText: Binding<String> {
        Binding(
            get: { claim.wrappedValue.counters.first?.text ?? "" },
            set: { text in
                var c = claim.wrappedValue
                if text.isEmpty {
                    c.counters = []
                } else if c.counters.isEmpty {
                    c.counters = [Counter(text: text)]
                } else {
                    c.counters[0].text = text
                }
                claim.wrappedValue = c
            })
    }

    var body: some View {
        Form {
            Section(isSub ? "Supporting point" : "Reason") {
                TextField(isSub ? "Something that backs this up" : "Because…", text: claim.text, axis: .vertical)
                    .lineLimit(1...5)
            }
            Section {
                Picker("Importance", selection: claim.importance) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(isSub ? "How much does the point above depend on this?" : "How much does your position depend on this?")
            } footer: {
                Text(Importance.label(claim.wrappedValue.importance))
            }

            Section {
                ForEach(claim.sources) { $source in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Where it comes from", text: $source.title)
                            .font(.body.weight(.semibold))
                        Picker("Kind", selection: $source.kind) {
                            ForEach(SourceKind.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("How others see it", selection: $source.lean) {
                            ForEach(Lean.allCases) { Text($0.label).tag($0) }
                        }
                        TextField("Link (optional)", text: $source.url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { claim.wrappedValue.sources.remove(atOffsets: $0) }
                Button("Add a source") { claim.wrappedValue.sources.append(Source()) }
            } header: {
                Text("Sources")
            } footer: {
                Text("Three independent sources you trust make the strongest support (IXI). Swipe to remove one.")
            }

            if map.depth(of: claim.wrappedValue) < 2 {
                Section("Supporting points") {
                    ForEach(map.children(of: claimID)) { kid in
                        NavigationLink(value: kid.id) {
                            Text(kid.text.isEmpty ? "(no words yet)" : kid.text)
                        }
                    }
                    Button("Add a supporting point") {
                        let kid = Claim(parent: claimID)
                        map.claims.append(kid)
                        path.append(kid.id)
                    }
                }
            }

            Section {
                Toggle("I don't have evidence for this. I just believe it.", isOn: claim.cloud)
            } footer: {
                Text("A belief cloud holds a little up. Too many and your head is in the clouds.")
            }

            Section {
                TextField("What would someone who disagrees say?", text: counterText, axis: .vertical)
                if !claim.wrappedValue.counters.isEmpty {
                    Picker("How strong is it?", selection: claim.counters[0].strength) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("I have an answer to it", isOn: claim.counters[0].answered)
                }
            } header: {
                Text("The strongest point against it")
            }

            Section {
                ForEach(Perspective.all) { p in
                    Toggle(p.label, isOn: Binding(
                        get: { claim.wrappedValue.disputedBy.contains(p.id) },
                        set: { on in
                            var c = claim.wrappedValue
                            c.disputedBy.removeAll { $0 == p.id }
                            if on { c.disputedBy.append(p.id) }
                            claim.wrappedValue = c
                        }))
                }
            } header: {
                Text("Who would reject this outright?")
            } footer: {
                Text("An opponent knocks these out before it attacks anything else.")
            }

            if showsSurvey {
                Section("How familiar are you with it?") {
                    FamiliarityPicker(value: claim.familiarity)
                }
                Section("How sure are you that it's true?") {
                    ConfidenceSlider(value: claim.confidence)
                }
            }

            Section {
                Button(isSub ? "Remove this point" : "Remove this reason", role: .destructive) {
                    let id = claimID
                    if path.isEmpty { dismiss() } else { path.removeLast() }
                    map.removeClaim(id)
                }
            }
        }
        .navigationTitle(isSub ? "Supporting point" : "Reason")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The five-step familiarity scale, from "no idea" to "researched it thoroughly".
struct FamiliarityPicker: View {
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Familiarity", selection: $value) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            Text(Familiarity.label(value))
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }
}

/// How sure, 0–100% in steps of 5.
struct ConfidenceSlider: View {
    @Binding var value: Int

    var body: some View {
        HStack {
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }), in: 0...100, step: 5)
                .tint(Theme.accent)
            Text("\(value)%")
                .font(Theme.mono(15, weight: .bold))
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How sure")
        .accessibilityValue("\(value) percent")
    }
}
