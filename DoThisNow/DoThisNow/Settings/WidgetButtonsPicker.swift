import SwiftUI
import DoThisNowKit

/// Settings > Start buttons: which Track activities the widgets can start.
struct WidgetButtonsPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var ids: [String]
    @Binding var changed: Bool

    var body: some View {
        let limit = AppModel.widgetButtonLimit
        Form {
            Section {
                if model.state.activities.isEmpty {
                    Text("Add the things you time on the Track tab first.")
                        .foregroundStyle(Theme.ink2)
                }
                ForEach(model.state.activities) { activity in
                    let isOn = ids.contains(activity.id)
                    Button {
                        toggle(activity.id)
                    } label: {
                        HStack {
                            Label(activity.name, systemImage: activity.symbol)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if isOn {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .disabled(!isOn && ids.count >= limit)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            } footer: {
                Text("Pick up to \(limit). Small widgets show the first two, medium ones all \(limit), and the Lock Screen button starts the first. Tap Save in Settings to keep your picks.")
            }
        }
        .tint(Theme.accent)
        .navigationTitle("Start buttons")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ id: String) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else if ids.count < AppModel.widgetButtonLimit {
            ids.append(id)
        }
        changed = true
    }
}
