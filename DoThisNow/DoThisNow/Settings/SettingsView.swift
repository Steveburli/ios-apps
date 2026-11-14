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
                Section {
                    Button(model.state.inbox.reminders.on ? "Apple Reminders: connected" : "Connect Apple Reminders") {
                        model.sheet = .inboxSettings
                    }
                } header: {
                    Text("Where tasks come from")
                }

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
                    Toggle("Task heat colors", isOn: $draft.taskHeat)
                    if draft.taskHeat {
                        HStack(spacing: 8) {
                            Text("Cold").font(.caption).foregroundStyle(Theme.ink3)
                            LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.25).map { Theme.heat(TaskHeat(value: $0)) },
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(height: 8)
                                .clipShape(Capsule())
                            Text("Hot").font(.caption).foregroundStyle(Theme.ink3)
                        }
                        .accessibilityHidden(true)
                    }
                } footer: {
                    Text("Blue is cold, red is hot, from priority and how close the deadline is. Each Not now warms a task up. Once a deadline passes, the task turns red and grows a little each day late, for up to 5 days. A later deadline is a fresh start.")
                }

                Section {
                    Toggle("Sounds", isOn: $draft.sound)
                } footer: {
                    Text("A chime when your timer runs out, and Sleep grumbling when you push bedtime. Sounds follow the silent switch.")
                }

                Section {
                    Text("Your tasks are saved on this iPhone and nothing is sent anywhere. Deleting the app erases everything here, but not what’s in Reminders.")
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
