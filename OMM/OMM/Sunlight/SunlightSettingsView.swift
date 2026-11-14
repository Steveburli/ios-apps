import SwiftUI
import OMMKit

/// The daily goal, reminder times, today's entries and a short note on why
/// daylight matters. General information only, not medical advice.
struct SunlightSettingsView: View {
    @Environment(SunlightModel.self) private var sunlight
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var sunlight = sunlight
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $sunlight.goalMinutes, in: SunlightLog.goalRange, step: SunlightLog.goalStep) {
                        Text("\(sunlight.goalMinutes) min a day")
                            .font(.headline.monospacedDigit())
                    }
                } header: {
                    Text("Daily goal")
                }

                Section {
                    Toggle("Remind me to go outside", isOn: $sunlight.remindersOn)
                        .tint(Theme.primary)
                    if sunlight.remindersOn {
                        timePicker("Morning", .morning)
                        timePicker("Midday, if under half", .midday)
                        timePicker("Last call, if not met", .lastCall)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Reminders stop for the day once you reach your goal. Set the last call about an hour before sunset.")
                }

                let today = sunlight.log.entries(on: Date())
                if !today.isEmpty {
                    Section {
                        ForEach(today) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(entry.minutes) min · \(entry.kind.title)")
                                        .font(.body.weight(.semibold))
                                    Text(entry.start.formatted(date: .omitted, time: .shortened))
                                        .font(.footnote)
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text("+\(entry.creditedMinutes)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(SunlightCard.sun)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { sunlight.remove(today[index]) }
                        }
                    } header: {
                        Text("Today")
                    } footer: {
                        Text("Swipe left to remove one.")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your body clock is set mostly by bright light reaching your eyes, and morning light matters most. Even a cloudy sky is many times brighter than a lit room.")
                        Text("Glass and car roofs cut much of that light, so time behind glass counts for less here. The full, half and quarter credits are rough rules of thumb, not measurements.")
                        Text("This is general information, not medical advice. If you have questions about sleep, mood or sun exposure, ask your doctor.")
                            .foregroundStyle(Theme.muted)
                    }
                    .font(.footnote)
                    .padding(.vertical, 4)
                } header: {
                    Text("About daylight")
                }
            }
            .navigationTitle("Sunlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
    }

    private func timePicker(_ title: String, _ kind: SunlightReminder.Kind) -> some View {
        DatePicker(title, selection: Binding(get: { sunlight.time(for: kind) },
                                             set: { sunlight.setTime($0, for: kind) }),
                   displayedComponents: .hourAndMinute)
    }
}
