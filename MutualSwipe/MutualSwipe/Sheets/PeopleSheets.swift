import SwiftUI
import CloudKit
import MutualKit

/// "Who’s swiping?": pick your name, or add it.
struct PlayerSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let groupID: String
    @State private var name = ""

    var body: some View {
        let me = session.me(in: groupID, store: store)
        let players = store.players(in: groupID)
        NavigationStack {
            List {
                Section {
                    if players.isEmpty {
                        Text("No one yet. Add your name to start.").foregroundStyle(Theme.muted)
                    }
                    ForEach(players) { player in
                        Button {
                            choose(player)
                        } label: {
                            HStack(spacing: 12) {
                                PlayerDot(player: player, size: 34)
                                Text(player.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                if player.id == me {
                                    Text("On this phone").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .accessibilityAddTraits(player.id == me ? .isSelected : [])
                    }
                } footer: {
                    Text("Pick your name. This phone remembers it. Passing the phone around? Switch here between turns.")
                }

                if store.canWrite(groupID) || store.groups[groupID] == nil {
                    Section("New person") {
                        HStack {
                            TextField("Add your name", text: $name)
                                .textContentType(.givenName)
                                .submitLabel(.done)
                                .onSubmit(add)
                            Button("Add", action: add)
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Who’s swiping?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func choose(_ player: Player) {
        session.setMe(player.id, in: groupID)
        session.show("Swiping as \(player.name)")
        dismiss()
    }

    private func add() {
        if let player = store.addPlayer(named: name, to: groupID) {
            name = ""
            choose(player)
        }
    }
}

/// Groups: which one you're in, inviting people, and leaving or deleting.
struct GroupsSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renaming: SwipeGroup?
    @State private var renameText = ""
    @State private var removing: SwipeGroup?

    var body: some View {
        let current = session.group(in: store)
        NavigationStack {
            List {
                if !store.isSignedIn && store.accountStatus != .couldNotDetermine {
                    Section {
                        Text("Sign in to iCloud in the Settings app to share groups with people on other iPhones. Until then, everything stays on this phone.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Section {
                    ForEach(store.sortedGroups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                session.currentGroupID = group.id
                                session.path = []
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                        Text(subtitle(group)).font(.caption).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    if group.id == current?.id {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            HStack(spacing: 8) {
                                if group.isOwned {
                                    Button(group.isShared ? "Manage people" : "Invite people") { invite(group) }
                                        .buttonStyle(.mutual())
                                    Button("Rename") {
                                        renameText = group.name
                                        renaming = group
                                    }
                                    .buttonStyle(.mutual(.quiet))
                                }
                                Button(group.isOwned ? "Delete" : "Leave") { removing = group }
                                    .buttonStyle(.mutual(.danger))
                            }
                            .font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Your groups")
                } footer: {
                    Text("Everyone in a group sees all of its decks. Make separate groups for, say, family and friends.")
                }

                Section("New group") {
                    HStack {
                        TextField("Name it", text: $newName)
                            .submitLabel(.done)
                            .onSubmit(create)
                        Button("Create", action: create)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename group", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let group = renaming { store.renameGroup(group.id, to: renameText) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog(removeTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible, presenting: removing) { group in
                Button(group.isOwned ? "Delete for everyone" : "Leave group", role: .destructive) {
                    store.removeGroup(group.id)
                    if session.currentGroupID == group.id { session.currentGroupID = nil }
                    session.path = []
                    removing = nil
                }
            } message: { group in
                Text(group.isOwned
                     ? "Its decks, cards and votes are deleted from iCloud, and anyone you invited loses access."
                     : "Its decks disappear from this phone. You can rejoin if someone invites you again.")
            }
        }
    }

    private var removeTitle: String {
        guard let group = removing else { return "" }
        return group.isOwned ? "Delete “\(group.name)”?" : "Leave “\(group.name)”?"
    }

    private func subtitle(_ group: SwipeGroup) -> String {
        let decks = store.decks(in: group.id).count
        var bits = ["\(decks) deck\(decks == 1 ? "" : "s")"]
        if group.isOwned {
            bits.append(group.isShared ? (group.participants.isEmpty ? "Shared" : "With \(group.participants.formatted(.list(type: .and)))") : "Only you")
        } else {
            bits.append(group.readOnly ? "Shared with you, view only" : "Shared with you")
        }
        return bits.joined(separator: " · ")
    }

    private func create() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let group = store.createGroup(named: trimmed)
        session.currentGroupID = group.id
        session.path = []
        newName = ""
        dismiss()
    }

    private func invite(_ group: SwipeGroup) {
        Task {
            do {
                let share = try await store.share(for: group.id)
                dismiss()
                try? await Task.sleep(for: .milliseconds(400))
                SharingPresenter.present(share: share, container: store.container, title: group.name)
            } catch {
                session.show(error.localizedDescription)
            }
        }
    }
}

/// Name a new deck and say what's in it.
struct NewDeckSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind: DeckKind = .dates
    @State private var blurb = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Name it, then add the cards you want to swipe on.")
                        .foregroundStyle(Theme.muted)
                    Field(label: "Name", text: $title, placeholder: "Friday movie night")
                        .focused($titleFocused)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What’s in it?").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        FlowLayout {
                            ForEach(DeckKind.allCases) { option in
                                Button {
                                    kind = option
                                } label: {
                                    Text(option.plural)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(kind == option ? Theme.bg : Theme.ink)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(kind == option ? Theme.ink : Theme.surface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(kind == option ? Theme.ink : Theme.line, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(kind == option ? .isSelected : [])
                            }
                        }
                    }
                    Field(label: "Note (optional)", text: $blurb, placeholder: "Budget, timing, anything to keep in mind")
                    Button("Create deck", action: create)
                        .buttonStyle(.mutual(wide: true))
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("New deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { titleFocused = true }
        }
    }

    private func create() {
        let group = session.group(in: store) ?? store.ensureGroup()
        guard store.canWrite(group.id) else {
            session.show(Session.readOnlyMessage)
            return
        }
        guard let deck = store.createDeck(in: group.id, title: title, kind: kind, blurb: blurb) else { return }
        session.currentGroupID = group.id
        session.openingTab[deck.id] = .cards
        dismiss()
        session.path.append(deck.id)
    }
}
