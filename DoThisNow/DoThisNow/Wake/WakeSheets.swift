import SwiftUI
import CoreImage.CIFilterBuiltins
import DoThisNowKit

/// One step of the morning routine.
struct RoutineStepForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let stepID: String?
    @State private var title = ""
    @State private var setByHand = false
    @State private var minutes = 10
    @State private var loaded = false

    var body: some View {
        let estimate = model.state.estimate(title: title, activityID: existing?.activityID)
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Make coffee", text: $title)
                        .font(.headline)
                }
                Section {
                    Toggle("Set the time myself", isOn: $setByHand)
                    if setByHand {
                        MinuteStepper(title: "Takes", minutes: $minutes, range: 1...180, step: 1)
                    }
                } footer: {
                    if !setByHand {
                        Text(title.isEmpty ? "" : "Using \(TimeText.duration(estimate.minutes)): \(estimate.detail). Time it on the Track tab and this updates on its own.")
                    }
                }
                if stepID != nil {
                    Section {
                        Button("Remove from my morning", role: .destructive) {
                            model.saveWake { $0.routine.removeAll { $0.id == stepID } }
                            dismiss()
                        }
                    }
                }
            }
            .tint(Theme.accent)
            .navigationTitle(stepID == nil ? "Add a step" : "Morning step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    title = existing.title
                    setByHand = existing.minutes != nil
                    minutes = existing.minutes ?? estimate.minutes
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var existing: RoutineStep? {
        model.state.wake.routine.first { $0.id == stepID }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let activityID = existing?.activityID ?? model.state.activity(matching: name)?.id
        model.saveWake { wake in
            if let index = wake.routine.firstIndex(where: { $0.id == stepID }) {
                wake.routine[index].title = name
                wake.routine[index].minutes = setByHand ? minutes : nil
                if wake.routine[index].activityID == nil { wake.routine[index].activityID = activityID }
            } else {
                wake.routine.append(RoutineStep(title: name, activityID: activityID, minutes: setByHand ? minutes : nil))
            }
        }
        dismiss()
    }
}

/// Sleep goal, falling asleep, buffer and commute.
struct SleepSettingsForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = WakeSettings()
    @State private var commuteByHand = false
    @State private var commuteMinutes = 20
    @State private var loaded = false

    var body: some View {
        let commuteEstimate = model.state.estimate(title: draft.commute.title, activityID: draft.commute.activityID)
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $draft.sleepMinutes, in: 300...720, step: 15) {
                        LabeledContent("Sleep goal", value: TimeText.duration(draft.sleepMinutes))
                    }
                    Stepper(value: $draft.fallAsleep, in: 0...90, step: 5) {
                        LabeledContent("Time to fall asleep", value: "\(draft.fallAsleep) min")
                    }
                } footer: {
                    Text("Bedtime is your wake-up time minus both of these.")
                }
                Section {
                    Toggle("I commute to work", isOn: $draft.commuteOn)
                    if draft.commuteOn {
                        Toggle("Set the commute myself", isOn: $commuteByHand)
                        if commuteByHand {
                            MinuteStepper(title: "Commute", minutes: $commuteMinutes, range: 1...240, step: 1)
                        } else {
                            LabeledContent("Commute", value: TimeText.duration(commuteEstimate.minutes))
                        }
                    }
                    Stepper(value: $draft.buffer, in: 0...60, step: 5) {
                        LabeledContent("Buffer before leaving", value: "\(draft.buffer) min")
                    }
                } header: {
                    Text("Getting out the door")
                } footer: {
                    Text(draft.commuteOn && !commuteByHand
                         ? "The commute is \(commuteEstimate.detail). Time it on the Track tab as “\(draft.commute.title)”. Work hours are in Settings."
                         : "Work hours are in Settings. On days with an earlier event, you leave for that instead.")
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Sleep and commute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = draft
                        saved.commute.minutes = commuteByHand ? commuteMinutes : nil
                        model.saveWake { $0 = saved }
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                draft = model.state.wake
                commuteByHand = draft.commute.minutes != nil
                commuteMinutes = draft.commute.minutes ?? commuteEstimate.minutes
            }
        }
    }
}

/// Days, time, codes and backups for the alarm.
struct AlarmSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var printing: WakeCode?

    private let weekdays: [(index: Int, label: String)] = [
        (1, "Mon"), (2, "Tue"), (3, "Wed"), (4, "Thu"), (5, "Fri"), (6, "Sat"), (0, "Sun"),
    ]

    var body: some View {
        let alarm = model.state.wake.alarm
        NavigationStack {
            Form {
                Section {
                    Picker("Ring at", selection: Binding(get: { alarm.followPlan }, set: { value in model.saveWake { $0.alarm.followPlan = value } })) {
                        Text("My suggested wake-up time").tag(true)
                        Text("A set time").tag(false)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if !alarm.followPlan {
                        MinuteOfDayPicker(title: "Time", minutes: Binding(get: { alarm.time }, set: { value in model.saveWake { $0.alarm.time = value } }))
                    }
                    FlowLayout {
                        ForEach(weekdays, id: \.index) { day in
                            Chip(title: day.label, isOn: alarm.days.contains(day.index)) {
                                model.saveWake { wake in
                                    if let index = wake.alarm.days.firstIndex(of: day.index) {
                                        wake.alarm.days.remove(at: index)
                                    } else {
                                        wake.alarm.days.append(day.index)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("When")
                } footer: {
                    Text(alarm.followPlan ? "It moves with your plan: earlier on days with an early event, later when your morning gets faster." : "")
                }

                Section {
                    Toggle("Scan a code to turn it off", isOn: Binding(get: { alarm.requireScan },
                                                                       set: { value in model.saveWake { $0.alarm.requireScan = value } }))
                    if alarm.requireScan {
                        ForEach(alarm.codes) { code in
                            HStack {
                                Label(code.name, systemImage: code.payload.hasPrefix(QRCode.prefix) ? "qrcode" : "barcode")
                                Spacer()
                                if code.payload.hasPrefix(QRCode.prefix) {
                                    Button("Print") { printing = code }
                                        .buttonStyle(.borderless)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { model.deleteCode(alarm.codes[index].id) }
                        }
                        Button("Scan a barcode or QR code") { model.scanMode = .addCode }
                        Button("Make a QR code to print") {
                            let code = QRCode.make()
                            model.addCode(name: "Printed QR code", payload: code)
                            printing = model.state.wake.alarm.codes.first { $0.payload == code }
                        }
                    }
                } header: {
                    Text("Turning it off")
                } footer: {
                    Text("Scan something that’s away from your bed, like the barcode on your toothpaste or coffee, or a QR code you print and stick by the bathroom mirror.")
                }

                if alarm.requireScan {
                    Section {
                        Stepper(value: Binding(get: { alarm.backupEvery }, set: { value in model.saveWake { $0.alarm.backupEvery = value } }),
                                in: 1...10) {
                            LabeledContent("Ring again every", value: "\(alarm.backupEvery) min")
                        }
                        Stepper(value: Binding(get: { alarm.backups }, set: { value in model.saveWake { $0.alarm.backups = value } }),
                                in: 1...30) {
                            LabeledContent("Up to", value: "\(alarm.backups) times")
                        }
                    } header: {
                        Text("Backups")
                    } footer: {
                        Text("iPhone always puts its own Stop slider on alarms, so the backups are what make scanning count: stop it without scanning and it rings again. If you ever can’t scan, the scanner has a button you hold for 30 seconds.")
                    }
                }

                Section {
                    Button("Test it: ring in a minute") {
                        Task { await model.testAlarm() }
                    }
                }
            }
            .tint(Theme.accent)
            .navigationTitle("Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
            .sheet(item: $printing) { code in
                QRCodeSheet(code: code)
            }
        }
    }
}

/// A QR code made by the app, to print or save.
enum QRCode {
    static let prefix = "DoThisNow-wake-"

    static func make() -> String {
        prefix + UUID().uuidString
    }

    static func image(_ payload: String, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

private struct QRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let code: WakeCode

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image = QRCode.image(code.payload) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("QR code for \(code.name)")
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("Wake-up code", image: Image(uiImage: image))) {
                        Label("Print or save", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.dtn(.primary))
                }
                Text("Print it and put it somewhere you have to walk to, like the bathroom or the kitchen.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle(code.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
