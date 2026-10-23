import SwiftUI
import DoThisNowKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PlannerSettings()
    @State private var loaded = false
    @State private var confirmingErase = false

    private let weekdays: [(index: Int, label: String)] = [
        (1, "Mon"), (2, "Tue"), (3, "Wed"), (4, "Thu"), (5, "Fri"), (6, "Sat"), (0, "Sun"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Your day") {
                    MinuteOfDayPicker(title: "I wake up at", minutes: $draft.wake)
                    MinuteOfDayPicker(title: "Bedtime", minutes: $draft.bed)
                    MinuteOfDayPicker(title: "Dinner at", minutes: $draft.dinnerAt)
                    Picker("Usual dinner", selection: $draft.dinner) {
                        ForEach(DinnerMode.allCases, id: \.self) { mode in
                            Text(mode.minutes > 0 ? "\(mode.label) (\(mode.minutes) min)" : mode.label).tag(mode)
                        }
                    }
                }

                Section {
                    Toggle("Block out work hours", isOn: $draft.work.on)
                    if draft.work.on {
                        FlowLayout {
                            ForEach(weekdays, id: \.index) { day in
                                Chip(title: day.label, isOn: draft.work.days.contains(day.index)) { toggle(day.index) }
                            }
                        }
                        .padding(.vertical, 4)
                        MinuteOfDayPicker(title: "From", minutes: $draft.work.start)
                        MinuteOfDayPicker(title: "To", minutes: $draft.work.end)
                    }
                } header: {
                    Text("Work")
                } footer: {
                    Text("A rock: nothing moves it.")
                }

                Section {
                    MinuteStepper(title: "Suggest a coffee shop or library when computer work piles up past",
                                  minutes: $draft.cafeMinutes, range: 15...960, step: 15)
                }

                Section {
                    Toggle("Sounds", isOn: $draft.sound)
                } footer: {
                    Text("A chime when your timer runs out, and Sleep grumbling when you push bedtime. Sounds follow the silent switch.")
                }

                Section {
                    Text("Your tasks are saved on this iPhone. Nothing is sent anywhere, except that if you connect Google Tasks, the app talks to Google directly to read and tick off your tasks. Deleting the app erases everything.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                    if model.state.hasExamples {
                        Button("Remove example tasks") { model.removeExamples() }
                    } else {
                        Button("Load example tasks") { model.loadExamples() }
                    }
                    Button("Erase everything", role: .destructive) { confirmingErase = true }
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.saveSettings(draft) }
                        .fontWeight(.bold)
                }
            }
            .confirmationDialog("Erase all tasks and events?", isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { model.eraseEverything() }
            } message: {
                Text("This can’t be undone.")
            }
            .onAppear {
                if !loaded {
                    draft = model.state.settings
                    loaded = true
                }
            }
        }
    }

    private func toggle(_ weekday: Int) {
        if let index = draft.work.days.firstIndex(of: weekday) {
            draft.work.days.remove(at: index)
        } else {
            draft.work.days.append(weekday)
        }
    }
}
