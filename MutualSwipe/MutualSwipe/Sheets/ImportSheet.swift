import SwiftUI
import PhotosUI
import MutualKit

/// "Add many cards": paste a list, ask any AI app, read a photo or open a
/// file. Every route ends on the same preview, where you drop what you don't
/// want before the cards are added.
struct ImportSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    /// The deck to add to. Nil when a file was opened from another app, so you pick one here.
    let deckID: String?

    @State private var text = ""
    @State private var request = ""
    @State private var promptCopied = false
    @State private var drafts: [CardDraft] = []
    @State private var dropped: Set<Int> = []
    @State private var targetDeckID: String?
    @State private var newDeckName = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var reading = false
    @State private var problem: String?

    private var deck: Deck? { (targetDeckID ?? deckID).flatMap { store.decks[$0] } }
    private var kept: [CardDraft] { drafts.enumerated().filter { !dropped.contains($0.offset) }.map(\.element) }

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    sources
                } else {
                    preview
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(drafts.isEmpty ? "Add many cards" : "Check the cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear(perform: takePending)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await readPhotos(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                openFile(url)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { Task { await readImages([image]) } }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Where the cards come from

    private var sources: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let problem {
                    Text(problem)
                        .font(.subheadline)
                        .foregroundStyle(Vote.never.color)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Vote.never.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Panel {
                    Label("Paste a list", systemImage: "list.bullet").font(Theme.display(18, weight: .bold))
                    TextField("One card per line", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .padding(12)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1.5))
                        .accessibilityLabel("Cards to add, one per line")
                    HStack(spacing: 10) {
                        PasteButton(payloadType: String.self) { strings in
                            let pasted = strings.joined(separator: "\n")
                            Task { @MainActor in show(CardImport.parse(pasted), from: "the clipboard") }
                        }
                        .buttonBorderShape(.capsule)
                        .tint(Theme.accent)
                        Button("Preview") { show(CardImport.parse(text), from: "that list") }
                            .buttonStyle(.mutual(.quiet))
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Panel {
                    Label("Ask an AI", systemImage: "sparkles").font(Theme.display(18, weight: .bold))
                    Text("Say what you want, copy the prompt into ChatGPT, Claude or any AI app, then copy its whole answer and paste it here.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Field(label: "What should the deck have?", text: $request,
                          placeholder: "The most popular movies streaming for free")
                    HStack(spacing: 10) {
                        Button(promptCopied ? "Copied" : "Copy the prompt") {
                            UIPasteboard.general.string = CardImport.aiPrompt(for: request, kind: deck?.kind ?? .other,
                                                                             deckTitle: deck?.title ?? "")
                            promptCopied = true
                        }
                        .buttonStyle(.mutual())
                        if promptCopied {
                            PasteButton(payloadType: String.self) { strings in
                                let pasted = strings.joined(separator: "\n")
                                Task { @MainActor in show(CardImport.parse(pasted), from: "the AI’s answer") }
                            }
                            .buttonBorderShape(.capsule)
                            .tint(Theme.accent)
                            .accessibilityLabel("Paste the answer")
                        }
                    }
                }

                Panel {
                    Label("From a photo", systemImage: "camera").font(Theme.display(18, weight: .bold))
                    Text("A menu, a list on paper or a screenshot. Mutual reads the words and makes one card per line.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                            Text("Choose photos")
                        }
                        .buttonStyle(.mutual(.quiet))
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take a photo") { showCamera = true }
                                .buttonStyle(.mutual(.quiet))
                        }
                    }
                    if reading {
                        ProgressView("Reading the words…").font(.footnote)
                    }
                }

                Panel {
                    Label("From a file", systemImage: "doc.text").font(Theme.display(18, weight: .bold))
                    Text("A spreadsheet saved as CSV, or a text file. Columns named title, details, link and tags are picked up. You can also open a CSV in Mutual from Mail, Messages or Files.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Button("Choose a file") { showFiles = true }
                        .buttonStyle(.mutual(.quiet))
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Preview

    private var preview: some View {
        List {
            Section {
                ForEach(Array(drafts.enumerated()), id: \.offset) { index, draft in
                    let isKept = !dropped.contains(index)
                    Button {
                        if isKept { dropped.insert(index) } else { dropped.remove(index) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: isKept ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isKept ? Theme.accent : Theme.muted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.title).font(.body.weight(.semibold)).foregroundStyle(isKept ? Theme.ink : Theme.muted)
                                    .strikethrough(!isKept)
                                let more = [draft.subtitle, draft.details].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !more.isEmpty {
                                    Text(more).font(.footnote).foregroundStyle(Theme.muted).lineLimit(2)
                                }
                                if !draft.link.isEmpty {
                                    Text(CardText.host(draft.link)).font(.caption).foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isKept ? .isSelected : [])
                    .accessibilityHint(isKept ? "Tap to leave this card out" : "Tap to add this card back")
                }
            } header: {
                Text("\(kept.count) card\(kept.count == 1 ? "" : "s") will be added")
                    .font(.subheadline.weight(.bold))
                    .textCase(nil)
            } footer: {
                Text("Tap a card to leave it out. You can edit any card after it’s added.")
            }

            if deckID == nil {
                Section("Add them to") {
                    let decks = session.group(in: store).map { store.decks(in: $0.id) } ?? []
                    Picker("Deck", selection: $targetDeckID) {
                        Text("A new deck").tag(String?.none)
                        ForEach(decks) { deck in
                            Text(deck.title).tag(Optional(deck.id))
                        }
                    }
                    if targetDeckID == nil {
                        TextField("New deck name", text: $newDeckName)
                    }
                }
            }

            Section {
                Button("Add \(kept.count) card\(kept.count == 1 ? "" : "s")", action: add)
                    .buttonStyle(.mutual(wide: true))
                    .disabled(kept.isEmpty)
                    .listRowBackground(Color.clear)
                Button("Start over") {
                    drafts = []
                    dropped = []
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Doing it

    private func show(_ found: [CardDraft], from source: String) {
        if found.isEmpty {
            problem = "Couldn’t find any cards in \(source). Put one card per line and try again."
        } else {
            problem = nil
            dropped = []
            drafts = found
        }
    }

    private func takePending() {
        guard let pending = session.pendingImport else { return }
        session.pendingImport = nil
        newDeckName = pending.name
        show(CardImport.parse(pending.text, isCSV: pending.isCSV), from: "“\(pending.name)”")
    }

    private func openFile(_ url: URL) {
        guard let pending = Session.PendingImport(fileURL: url) else {
            problem = "Couldn’t read that file. Save it as CSV or plain text and try again."
            return
        }
        show(CardImport.parse(pending.text, isCSV: pending.isCSV), from: "that file")
    }

    private func readPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        await readImages(images)
    }

    private func readImages(_ images: [UIImage]) async {
        reading = true
        defer { reading = false }
        var text = ""
        for image in images {
            text += await TextReader.read(image) + "\n"
        }
        show(CardImport.parseLines(text), from: "the photo")
    }

    private func add() {
        var target = deck
        if target == nil {
            let group = session.group(in: store) ?? store.ensureGroup()
            guard store.canWrite(group.id) else {
                session.show(Session.readOnlyMessage)
                return
            }
            let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
            target = store.createDeck(in: group.id, title: name.isEmpty ? "New deck" : name, kind: .other, blurb: "")
            session.currentGroupID = group.id
        }
        guard let target else { return }
        guard store.canWrite(target.groupID) else {
            session.show(Session.readOnlyMessage)
            return
        }
        let added = store.addCards(kept, to: target.id)
        session.show("Added \(added) card\(added == 1 ? "" : "s") to “\(target.title)”")
        dismiss()
        if deckID == nil {
            session.openingTab[target.id] = .cards
            session.path = [target.id]
        }
    }
}
