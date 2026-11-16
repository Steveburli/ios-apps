import SwiftUI
import DoThisNowKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = PlannerSettings()
    @State private var loaded = false
    @State private var confirmingErase = false
    /// The activities with start buttons on widgets; set when you change them here.
    @State private var widgetIDs: [String] = []
    @State private var widgetIDsChanged = false

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
                    Toggle("Lock my work meetings", isOn: Binding(
                        get: { model.state.meetingSettings.on },
                        set: { on in Task { await model.setMeetingsOn(on) } }))
                    if model.state.meetingSettings.on {
                        if let problem = model.meetingsProblem {
                            Text(problem)
                                .font(.footnote)
                                .foregroundStyle(Theme.ink2)
                        }
                        ForEach(model.meetingCalendars) { list in
                            Toggle(list.name, isOn: Binding(
                                get: { model.state.meetingSettings.locks(calendarID: list.id, name: list.name) },
                                set: { model.setCalendarLocked(list, $0) }))
                        }
                    }
                } header: {
                    Text("Work meetings")
                } footer: {
                    Text("Meetings from the calendars switched on here (Alignops to start) keep their exact times and show a lock. You can still put tasks in work hours: anything dropped on a meeting moves to the next open gap.")
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
                    Stepper(value: $draft.workPerBreak, in: 1...30) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Minutes of focus for 1 minute of break")
                            Text("\(draft.workPerBreak) min")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .accessibilityValue("\(draft.workPerBreak) minutes")
                } header: {
                    Text("Break bank")
                } footer: {
                    Text("Focus time and timed sessions earn break time. Leftover break time is gone the next morning, but time you owe carries over.")
                }

                Section {
                    NavigationLink {
                        WidgetButtonsPicker(ids: $widgetIDs, changed: $widgetIDsChanged)
                    } label: {
                        LabeledContent("Start buttons", value: widgetSummary)
                    }
                } header: {
                    Text("Widgets and Lock Screen")
                } footer: {
                    Text("Pick what the Home Screen and Lock Screen widgets can start. Running timers also show on the Lock Screen and in the Dynamic Island, with a Stop button.")
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
                    Button("Save") {
                        if widgetIDsChanged { model.setWidgetActivities(widgetIDs) }
                        model.saveSettings(draft)
                    }
                        .fontWeight(.bold)
                }
            }
            .confirmationDialog("Erase all tasks and events?", isPresented: $confirmingErase, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { model.eraseEverything() }
            } message: {
                Text("This can’t be undone.")
            }
            .onAppear {
                model.refreshMeetings()
                if !loaded {
                    draft = model.state.settings
                    widgetIDs = model.widgetActivities.map(\.id)
                    loaded = true
                }
            }
        }
    }

    private var widgetSummary: String {
        if model.state.activities.isEmpty { return "Add activities on Track" }
        let names = model.state.activities.filter { widgetIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    private func toggle(_ weekday: Int) {
        if let index = draft.work.days.firstIndex(of: weekday) {
            draft.work.days.remove(at: index)
        } else {
            draft.work.days.append(weekday)
        }
    }
}
