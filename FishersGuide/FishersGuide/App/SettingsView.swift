import AVFoundation
import GuideKit
import SwiftUI

struct SettingsView: View {
    @Environment(GuideModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Toggle("\"Coming up\" heads-ups", isOn: $model.settings.trigger.headsUps)
                    VStack(alignment: .leading) {
                        Text("Voice speed")
                        Slider(value: $model.settings.rate, in: 0.4...0.6) {
                            Text("Voice speed")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                    }
                    Picker("Voice", selection: $model.settings.voiceID) {
                        Text("Best available").tag(String?.none)
                        ForEach(Narrator.englishVoices, id: \.identifier) { voice in
                            Text(voiceName(voice)).tag(Optional(voice.identifier))
                        }
                    }
                    Button("Hear a Sample") {
                        if let stop = model.pointsOfInterest.first {
                            model.narrator.play(Narrator.Narration(
                                stopID: stop.id, title: "Voice sample",
                                script: "Coming up on your right: \(stop.title).",
                                audioFile: nil, isTeaser: true))
                        }
                    }
                } header: {
                    Text("Narration")
                } footer: {
                    Text("For a more natural voice, download an Enhanced or Premium voice in the iPhone's Settings › Accessibility › Spoken Content › Voices.")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Start stories \(Int(model.settings.trigger.leadSeconds)) seconds early")
                        Slider(value: $model.settings.trigger.leadSeconds, in: 5...45, step: 5)
                    }
                } header: {
                    Text("Timing")
                } footer: {
                    Text("Stories begin before you reach a place, so they're underway as it comes into view. The faster you're going, the earlier they start.")
                }

                Section("Topics") {
                    ForEach(StopCategory.allCases, id: \.self) { category in
                        Toggle(isOn: categoryBinding(category)) {
                            Label(category.title, systemImage: category.symbol)
                        }
                    }
                }

                Section {
                    if model.history.isEmpty {
                        Text("Nothing yet. Start a tour, or try the demo drive.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.history.prefix(30)) { entry in
                            if let stop = model.tour.stop(id: entry.stopID) {
                                HStack {
                                    Text(stop.title)
                                    Spacer()
                                    Text(entry.missed ? "Missed" : entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.footnote)
                                        .foregroundStyle(entry.missed ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                                }
                            }
                        }
                    }
                    Button("Hear Every Story Again", role: .destructive) { confirmReset = true }
                        .disabled(model.history.isEmpty)
                } header: {
                    Text("Heard")
                } footer: {
                    Text("A story won't repeat for six hours, so you won't hear the same one on the way back. Reset to hear them all again now.")
                }

                Section("Demo drive") {
                    Picker("Speed", selection: $model.settings.demoSpeed) {
                        Text("30 mph").tag(13.4)
                        Text("45 mph").tag(20.0)
                        Text("50 mph").tag(22.0)
                        Text("60 mph").tag(26.8)
                    }
                }

                Section {
                    Text("Keep your eyes on the road. The guide is built to run hands-free: start the tour before you pull out and let the stories come to you. Use the Lock Screen, your car's controls or a passenger for pause and skip.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Drive safely")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Hear every story again?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset Heard Stories", role: .destructive) { model.resetHistory() }
            }
        }
    }

    private func categoryBinding(_ category: StopCategory) -> Binding<Bool> {
        Binding(
            get: { !model.settings.trigger.mutedCategories.contains(category) },
            set: { on in
                if on {
                    model.settings.trigger.mutedCategories.remove(category)
                } else {
                    model.settings.trigger.mutedCategories.insert(category)
                }
            }
        )
    }

    private func voiceName(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "\(voice.name) (Premium)"
        case .enhanced: "\(voice.name) (Enhanced)"
        default: voice.name
        }
    }
}
