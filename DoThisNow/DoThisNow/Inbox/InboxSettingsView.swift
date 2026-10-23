import SwiftUI
import AppIntents
import DoThisNowKit

/// Where Inbox tasks come from, and which ones get through.
struct InboxSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var connecting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Suggest tasks for the gaps", isOn: Binding(
                        get: { model.state.settings.autoFill },
                        set: { model.setAutoFill($0) }
                    ))
                } header: {
                    Text("On the Day")
                } footer: {
                    Text("When this is on, the Day also fills empty time with suggestions from your priorities. They flow around the blocks you place yourself.")
                }

                appSection
                remindersSection
                googleSection
                inboxSection

                if !model.state.inbox.hidden.isEmpty {
                    Section {
                        Button("Bring back \(model.state.inbox.hidden.count) hidden task\(model.state.inbox.hidden.count == 1 ? "" : "s")") {
                            model.unhideAll()
                        }
                    } footer: {
                        Text("Swipe left on an Inbox task to hide it for good.")
                    }
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Inbox sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
            .task { await model.refreshSources() }
        }
    }

    // MARK: Sources

    private var appSection: some View {
        Section {
            Toggle("Do This Now tasks", isOn: binding(.app, \.on))
            if model.state.inbox.app.on {
                ListToggles(source: .app, lists: Tier.all.map { AppModel.SourceList(id: "tier-\($0)", name: Tier.name($0)) })
                FilterRows(source: .app, showsPriority: false)
            }
        } header: {
            Text("Do This Now")
        } footer: {
            Text("Your own task list, by priority. Someday tasks stay out unless you turn them on.")
        }
    }

    private var remindersSection: some View {
        Section {
            if RemindersSource.shared.isAuthorized {
                Toggle("Apple Reminders", isOn: binding(.reminders, \.on))
                if model.state.inbox.reminders.on {
                    if model.reminderLists.isEmpty {
                        Text("No lists found yet.").foregroundStyle(Theme.ink3)
                    } else {
                        ListToggles(source: .reminders, lists: model.reminderLists)
                    }
                    FilterRows(source: .reminders, showsPriority: true)
                }
            } else {
                Button("Connect Apple Reminders") {
                    Task { await model.connectReminders() }
                }
            }
            if let problem = model.sourceProblem[.reminders] {
                Text(problem).font(.footnote).foregroundStyle(Theme.bad)
            }
        } header: {
            Text("Apple Reminders")
        } footer: {
            Text("Turn off lists you never plan, like groceries. Reminders tags aren’t shared with other apps, so to bring in only some reminders, put a word like “plan” in their notes and set it as the keyword.")
        }
    }

    private var googleSection: some View {
        Section {
            if !GoogleTasks.isConfigured {
                Text("Google sign-in is being set up and will work in an upcoming version.")
                    .foregroundStyle(Theme.ink2)
            } else if model.googleSignedIn {
                Toggle("Google Tasks", isOn: binding(.google, \.on))
                if model.state.inbox.google.on {
                    if !model.googleLists.isEmpty {
                        ListToggles(source: .google, lists: model.googleLists)
                    }
                    FilterRows(source: .google, showsPriority: false)
                }
                Button("Sign out of Google", role: .destructive) { model.disconnectGoogle() }
            } else {
                Button(connecting ? "Opening Google…" : "Sign in with Google") {
                    connecting = true
                    Task {
                        await model.connectGoogle()
                        connecting = false
                    }
                }
                .disabled(connecting)
            }
            if let problem = model.sourceProblem[.google] {
                Text(problem).font(.footnote).foregroundStyle(Theme.bad)
            }
        } header: {
            Text("Google Tasks")
        } footer: {
            Text("Do This Now reads your open Google tasks and ticks them off when you finish them here. Nothing else in your Google account is touched.")
        }
    }

    private var inboxSection: some View {
        Section {
            Toggle("Typed in, Shortcuts and Share", isOn: binding(.inbox, \.on))
            NavigationLink("Send tasks from other apps") {
                ShortcutsHelpView()
            }
        } header: {
            Text("Inbox")
        } footer: {
            Text("Tasks you type into the Inbox, or send with Siri, Shortcuts or a Share-button shortcut.")
        }
    }

    private func binding(_ source: TaskSource, _ path: WritableKeyPath<SourceFilter, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.state.inbox[source][keyPath: path] },
            set: { value in model.setFilter(source) { $0[keyPath: path] = value } }
        )
    }
}

/// One switch per list.
private struct ListToggles: View {
    @Environment(AppModel.self) private var model
    let source: TaskSource
    let lists: [AppModel.SourceList]

    var body: some View {
        DisclosureGroup("Lists (\(lists.filter { !hidden.contains($0.id) }.count) of \(lists.count))") {
            ForEach(lists) { list in
                Toggle(list.name, isOn: Binding(
                    get: { !hidden.contains(list.id) },
                    set: { on in
                        model.setFilter(source) { filter in
                            if on {
                                filter.hiddenLists.removeAll { $0 == list.id }
                            } else if !filter.hiddenLists.contains(list.id) {
                                filter.hiddenLists.append(list.id)
                            }
                        }
                    }
                ))
            }
        }
    }

    private var hidden: Set<String> {
        Set(model.state.inbox[source].hiddenLists)
    }
}

/// Due date, priority and keyword filters for one source.
private struct FilterRows: View {
    @Environment(AppModel.self) private var model
    let source: TaskSource
    let showsPriority: Bool

    var body: some View {
        let filter = model.state.inbox[source]
        Picker("Due", selection: Binding(get: { filter.due }, set: { value in model.setFilter(source) { $0.due = value } })) {
            ForEach(DueWindow.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        if filter.due != .any {
            Toggle("Also tasks with no due date", isOn: Binding(get: { filter.undated },
                                                                 set: { value in model.setFilter(source) { $0.undated = value } }))
        }
        if showsPriority {
            Picker("Priority", selection: Binding(get: { filter.minPriority },
                                                  set: { value in model.setFilter(source) { $0.minPriority = value } })) {
                Text("Any").tag(0)
                Text("Low and up").tag(1)
                Text("Medium and up").tag(2)
                Text("High only").tag(3)
            }
        }
        KeywordField(source: source, saved: filter.keyword)
    }
}

/// Saves the keyword when you're done typing, not on every letter.
private struct KeywordField: View {
    @Environment(AppModel.self) private var model
    let source: TaskSource
    let saved: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Text("Only with the word")
            TextField("any", text: $text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
        }
        .onAppear { text = saved }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { save() }
        }
    }

    private func save() {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if word != saved { model.setFilter(source) { $0.keyword = word } }
    }
}

/// How to send tasks to the Inbox from anywhere.
struct ShortcutsHelpView: View {
    var body: some View {
        List {
            Section {
                Text("Say “Add a task to Do This Now” to Siri, or use the **Add to Do This Now Inbox** action in the Shortcuts app.")
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
            } header: {
                Text("Siri and Shortcuts")
            }
            Section {
                step(1, "Open the Shortcuts app and tap **+** to make a new shortcut.")
                step(2, "Tap the **ⓘ** or the shortcut’s name, then turn on **Show in Share Sheet**.")
                step(3, "Add the action **Add to Do This Now Inbox**. For **Task**, choose **Shortcut Input**.")
                step(4, "Name it “Add to Do This Now”.")
                Text("Now the Share button in Mail, Safari, Notes, Messages and most other apps can send what you’re looking at to the Inbox. The first line becomes the task and the rest becomes notes.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
            } header: {
                Text("The Share button")
            }
            Section {
                Text("Apps with their own Shortcuts actions, like Todoist, Things or Notion, can feed the Inbox too: make a shortcut that gets their tasks and runs **Add to Do This Now Inbox** for each one. An Automation in the Shortcuts app can run it every morning.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
            } header: {
                Text("Other to-do apps")
            }
        }
        .navigationTitle("From other apps")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(Theme.accent)
            Text(text)
        }
    }
}
