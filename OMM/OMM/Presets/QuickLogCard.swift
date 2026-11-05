import SwiftUI
import OMMKit

/// Saved presets on the home screen, each with a one-tap Log button, for
/// routines with no time to use the app in between, like a machine circuit.
/// After a log, a bar with Undo covers a mis-tap.
struct QuickLogCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Quick Log")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        model.presetSheet = .new
                    } label: {
                        Label("New Preset", systemImage: "plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.primary)
                    }
                }
                if let note = model.quickLog {
                    noteBar(note)
                }
                if model.presets.isEmpty {
                    Text("Save a routine you do the same way every time, like a circuit of gym machines. Then one tap logs a set for each one.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(model.presets) { preset in
                        presetRow(preset)
                    }
                }
            }
        }
        .sensoryFeedback(.success, trigger: model.quickLog) { _, new in new != nil }
    }

    private func presetRow(_ preset: Preset) -> some View {
        HStack(spacing: 12) {
            Button {
                model.presetSheet = .edit(preset)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    Text("\(preset.totalSets.counted("set")) · \(preset.setsByGroup.count.counted("group")) · Edit")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the preset to change it")
            Button {
                model.logPreset(preset)
            } label: {
                Label("Log", systemImage: "checkmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!preset.isReady)
            .opacity(preset.isReady ? 1 : 0.45)
            .accessibilityLabel("Log \(preset.name)")
            .accessibilityHint("Adds one set to each of its muscle groups")
        }
        .padding(12)
        .background(Theme.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func noteBar(_ note: AppModel.QuickLogNote) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.success)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Logged \(note.presetName): \(note.sets.counted("set"))")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.text)
                if !note.finished.isEmpty {
                    Text("Crossed off: " + note.finished.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button("Undo") { model.undoQuickLog() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.primary)
            Button {
                model.dismissQuickLog()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Theme.success.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
