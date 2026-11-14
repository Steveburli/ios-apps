import SwiftUI
import MutualKit

// A deck's questions: people answer them before they swipe. The deck's
// questions are written here (or copied from a ready-made set), anyone can
// fill in anyone's answers, each person confirms their own, and everyone in
// the group can see all the answers. "Your ideas" answers become cards.

// MARK: Writing the questions

/// Write or change a deck's questions.
struct QuestionsSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let deckID: String

    @State private var drafts: [FormQuestion] = []
    @State private var loaded = false
    @State private var replacing: FormTemplate?

    var body: some View {
        NavigationStack {
            Group {
                if let deck = store.decks[deckID] {
                    content(deck)
                } else {
                    ContentUnavailableView("This deck was deleted", systemImage: "rectangle.stack.badge.minus")
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!store.canWrite(store.decks[deckID]?.groupID ?? ""))
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            drafts = store.decks[deckID]?.formQuestions ?? []
        }
    }

    private func content(_ deck: Deck) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("People answer these before they swipe on “\(deck.title)”. Everyone in the group sees the answers. Answers to a “Your ideas” question become new cards, with a Love from whoever suggested them.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)

                templates

                ForEach($drafts) { $question in
                    QuestionEditor(question: $question,
                                   number: (drafts.firstIndex { $0.id == question.id } ?? 0) + 1,
                                   canMoveUp: drafts.first?.id != question.id,
                                   canMoveDown: drafts.last?.id != question.id,
                                   move: { move(question.id, by: $0) },
                                   remove: { drafts.removeAll { $0.id == question.id } })
                }

                Menu {
                    ForEach(QuestionKind.allCases) { kind in
                        Button {
                            drafts.append(FormQuestion(kind: kind, prompt: "",
                                                       hint: kind == .ideas ? "One per line" : ""))
                        } label: {
                            Label(kind.label, systemImage: kind.symbol)
                        }
                    }
                } label: {
                    Label("Add a question", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.accent, in: Capsule())
                }
            }
            .padding(16)
        }
        .confirmationDialog("Replace your questions?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }),
                            titleVisibility: .visible, presenting: replacing) { template in
            Button("Replace with \(template.title)", role: .destructive) { drafts = template.makeQuestions() }
            Button("Add to the end") { drafts += template.makeQuestions() }
        } message: { template in
            Text("Use the \(template.title) questions instead of the ones here, or add them after.")
        }
    }

    private var templates: some View {
        Panel {
            Text(drafts.isEmpty ? "Start from a ready-made set" : "Ready-made sets").font(Theme.display(18, weight: .bold))
            Text("Copy one in, then change, add or remove anything.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            ForEach(FormTemplate.all) { template in
                Button {
                    if drafts.isEmpty { drafts = template.makeQuestions() } else { replacing = template }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: template.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 34, height: 34)
                            .background(Theme.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(template.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(template.blurb).font(.footnote).foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func move(_ id: String, by offset: Int) {
        guard let from = drafts.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard drafts.indices.contains(to) else { return }
        drafts.swapAt(from, to)
    }

    private func save() {
        let kept = drafts.compactMap { $0.cleaned() }
        store.setQuestions(kept, deck: deckID)
        session.show(kept.isEmpty ? "No questions on this deck" : "Saved \(kept.count) question\(kept.count == 1 ? "" : "s")")
        dismiss()
    }
}

/// One question in the editor.
private struct QuestionEditor: View {
    @Binding var question: FormQuestion
    let number: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        Panel {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 26, height: 26)
                    .background(Theme.accent, in: Circle())
                Menu {
                    Picker("Kind", selection: $question.kind) {
                        ForEach(QuestionKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                } label: {
                    Label(question.kind.label, systemImage: question.kind.symbol)
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Answer type: \(question.kind.label)")
                Spacer()
                Button { move(-1) } label: { Image(systemName: "arrow.up").frame(width: 36, height: 36) }
                    .disabled(!canMoveUp)
                    .accessibilityLabel("Move up")
                Button { move(1) } label: { Image(systemName: "arrow.down").frame(width: 36, height: 36) }
                    .disabled(!canMoveDown)
                    .accessibilityLabel("Move down")
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash").frame(width: 36, height: 36)
                }
                .accessibilityLabel("Delete question \(number)")
            }
            .foregroundStyle(Theme.ink)

            Field(label: "Question", text: $question.prompt, placeholder: "What do you want to know?", axis: .vertical)
            if question.kind == .choice {
                Field(label: "Choices, one per line", text: optionsText, placeholder: "Lots of chill time\nPacked with things to do",
                      axis: .vertical)
            }
            if question.kind == .text || question.kind == .ideas {
                Field(label: "Example (optional)", text: $question.hint, placeholder: "Shown in the empty answer")
            }
        }
    }

    /// Choices edited as lines of text. Empty lines are kept while typing and dropped on save.
    private var optionsText: Binding<String> {
        Binding(get: { question.options.joined(separator: "\n") },
                set: { question.options = $0.components(separatedBy: "\n") })
    }
}

// MARK: Answering

/// One person's answers. For yourself it ends in "Confirm", which turns your
/// ideas into cards. For someone else it saves them for that person to look
/// over and confirm.
struct AnswerSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let deckID: String
    let playerID: String

    @State private var values: [String: String] = [:]
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if let deck = store.decks[deckID], let player = store.players[playerID] {
                    content(deck, player: player)
                } else {
                    ContentUnavailableView("Nothing to answer here", systemImage: "questionmark.bubble")
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isMe ? "Later" : "Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            values = store.answers(deck: deckID, player: playerID)?.values ?? [:]
        }
    }

    private var me: String? {
        store.decks[deckID].flatMap { session.me(in: $0.groupID, store: store) }
    }

    private var isMe: Bool { me == playerID }

    private var title: String {
        if isMe { return "Your answers" }
        return store.players[playerID].map { "\($0.name)’s answers" } ?? "Answers"
    }

    private func content(_ deck: Deck, player: Player) -> some View {
        let saved = store.answers(deck: deckID, player: playerID)
        let canWrite = store.canWrite(deck.groupID)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                intro(deck, player: player, saved: saved)

                ForEach(deck.formQuestions) { question in
                    Panel {
                        AnswerField(question: question, value: binding(question), forMe: isMe)
                    }
                }

                if me == nil {
                    Text("Pick who’s swiping on this phone first, so your answers have your name on them.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    Button("Pick your name") { session.sheet = .player(deck.groupID) }
                        .buttonStyle(.mutual(wide: true))
                } else {
                    Button(isMe ? "Confirm and start swiping" : "Save for \(player.name)") { save(deck, player: player) }
                        .buttonStyle(.mutual(wide: true))
                        .disabled(!canWrite)
                        .padding(.top, 4)
                    if !canWrite {
                        Text(Session.readOnlyMessage).font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func intro(_ deck: Deck, player: Player, saved: FormAnswers?) -> some View {
        if isMe, let saved, saved.waitingOnConfirm {
            let by = store.players[saved.filledBy]?.name ?? "Someone"
            Label {
                Text("\(by) filled these in for you. Look them over, fix anything that’s off, then confirm.")
            } icon: {
                Image(systemName: "person.crop.circle.badge.checkmark")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if isMe {
            Text("A few questions before you swipe on “\(deck.title)”. Everyone in the group can see your answers.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        } else {
            Text("Filling in for \(player.name). They’ll see what you wrote and confirm it or fix it. Their ideas become cards when they confirm.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
    }

    private func binding(_ question: FormQuestion) -> Binding<String> {
        Binding(get: { values[question.id] ?? "" }, set: { values[question.id] = $0 })
    }

    private func save(_ deck: Deck, player: Player) {
        guard let me else { return }
        let result = store.saveAnswers(values, deck: deck.id, player: player.id, by: me)
        if me == player.id {
            var message = "Thanks! Your answers are in."
            if result.newCards > 0 {
                message = "Your \(result.newCards == 1 ? "idea is" : "\(result.newCards) ideas are") in the deck, with a Love from you."
            } else if result.matched > 0 {
                message = "Your answers are in. Your ideas were already cards, so they got a Love from you."
            }
            session.show(message)
        } else {
            session.show("Saved. \(player.name) will see them and confirm.")
        }
        dismiss()
    }
}

/// The answer to one question.
private struct AnswerField: View {
    let question: FormQuestion
    @Binding var value: String
    let forMe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.prompt)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            switch question.kind {
            case .text:
                box(TextField(question.hint.isEmpty ? "Your answer" : question.hint, text: $value, axis: .vertical)
                    .lineLimit(1...6))
            case .ideas:
                box(TextField(question.hint.isEmpty ? "One per line" : question.hint, text: $value, axis: .vertical)
                    .lineLimit(3...10))
                Text(forMe ? "Each line becomes a card everyone can swipe on, with a Love from you."
                           : "Each line becomes a card when they confirm.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            case .choice:
                chips(question.options)
            case .yesNo:
                chips(["Yes", "No"], stored: ["yes", "no"])
            case .date:
                dateField
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func box<V: View>(_ field: V) -> some View {
        field
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1.5))
            .accessibilityLabel(question.prompt)
    }

    /// Tap one to pick it, tap it again to clear.
    private func chips(_ labels: [String], stored: [String]? = nil) -> some View {
        FlowLayout {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let saved = stored?[index] ?? label
                let picked = value == saved
                Button {
                    value = picked ? "" : saved
                } label: {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(picked ? Theme.accentInk : Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(picked ? Theme.accent : Theme.sunk, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var dateField: some View {
        if let day = Forms.day(from: value) {
            HStack {
                DatePicker(question.prompt, selection: Binding(get: { day }, set: { value = Forms.dayString($0) }),
                           displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                Button("Clear") { value = "" }
                    .buttonStyle(.mutual(.quiet))
                    .controlSize(.small)
            }
        } else {
            Button {
                value = Forms.dayString(Date())
            } label: {
                Label("Pick a date", systemImage: "calendar")
            }
            .buttonStyle(.mutual(.quiet))
        }
    }
}

// MARK: Everyone's answers

/// Everyone's answers, side by side, with who still has to confirm.
struct AllAnswersSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let deckID: String

    var body: some View {
        NavigationStack {
            Group {
                if let deck = store.decks[deckID] {
                    content(deck)
                } else {
                    ContentUnavailableView("This deck was deleted", systemImage: "rectangle.stack.badge.minus")
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Everyone’s answers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if store.canWrite(store.decks[deckID]?.groupID ?? "") {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Edit questions") { session.sheet = .questions(deckID) }
                    }
                }
            }
        }
    }

    private func content(_ deck: Deck) -> some View {
        let me = session.me(in: deck.groupID, store: store)
        let players = store.players(in: deck.groupID)
        let canWrite = store.canWrite(deck.groupID)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if players.isEmpty {
                    Text("No one has joined this group yet.").foregroundStyle(Theme.muted)
                }
                ForEach(players) { player in
                    let saved = store.answers(deck: deck.id, player: player.id)
                    Panel {
                        HStack(spacing: 10) {
                            PlayerDot(player: player, size: 30)
                            Text(player.id == me ? "\(player.name) (you)" : player.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 6)
                            status(saved, player: player)
                        }
                        if let saved, saved.answered(deck.formQuestions) > 0 {
                            ForEach(deck.formQuestions) { question in
                                let shown = Forms.display(saved.value(question), for: question)
                                if !shown.isEmpty {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(question.prompt).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                                        Text(shown).font(.subheadline).foregroundStyle(Theme.ink)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                        if canWrite, me != nil {
                            Button(player.id == me ? (saved?.isConfirmed == true ? "Change my answers" : "Answer now")
                                                   : "Fill in for \(player.name)") {
                                session.sheet = .answer(deck.id, player.id)
                            }
                            .buttonStyle(.mutual(.quiet))
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func status(_ saved: FormAnswers?, player: Player) -> Pill {
        guard let saved else { return Pill(text: "Not answered") }
        if saved.isConfirmed {
            return Pill(text: "Confirmed", tint: Theme.accentInk, background: Theme.accent)
        }
        if saved.waitingOnConfirm {
            return Pill(text: "Needs their OK", tint: Theme.accent, background: Theme.accentSoft)
        }
        return Pill(text: "Not answered")
    }
}

// MARK: The bar on a deck

/// Above the stack on a deck with questions: how many people have confirmed,
/// and a button to answer or see everyone's answers.
struct QuestionsBar: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    let deck: Deck
    let me: String?

    var body: some View {
        let players = store.players(in: deck.groupID)
        let confirmed = players.filter { store.answers(deck: deck.id, player: $0.id)?.isConfirmed == true }.count
        let mine = me.flatMap { store.answers(deck: deck.id, player: $0) }
        let needsMe = store.needsAnswers(deck: deck.id, player: me)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("QUESTIONS · \(confirmed) OF \(players.count) DONE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(needsMe ? Theme.accent : Theme.muted)
                Text(needsMe ? (mine?.waitingOnConfirm == true ? "Your answers need your OK" : "Answer before you swipe")
                             : "Your answers are in")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 6)
            if needsMe, let me {
                Button(mine?.waitingOnConfirm == true ? "Check" : "Answer") { session.sheet = .answer(deck.id, me) }
                    .buttonStyle(.mutual())
                    .controlSize(.small)
            }
            Button("See all") { session.sheet = .allAnswers(deck.id) }
                .buttonStyle(.mutual(.quiet))
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(needsMe ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }
}
