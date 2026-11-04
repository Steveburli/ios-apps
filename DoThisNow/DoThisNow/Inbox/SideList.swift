import SwiftUI
import DoThisNowKit

/// The iPad's left column: the Inbox from every source, or only Do This
/// Now's own tasks. Drag a task onto the timeline to give it a time, and drag
/// a block back here to take it off the day.
struct SideList: View {
    @Environment(AppModel.self) private var model
    let day: CalendarDay
    @State private var newTitle = ""
    @FocusState private var typing: Bool

    var body: some View {
        @Bindable var model = model
        let all = model.inboxEntries
        let entries = model.sideList == .tasks ? all.filter { $0.task.ref.source == .app } : all

        VStack(spacing: 0) {
            Picker("Show", selection: $model.sideList) {
                Text("Inbox (\(all.count))").tag(AppModel.SideListMode.inbox)
                Text("Do This Now tasks").tag(AppModel.SideListMode.tasks)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            HStack(spacing: 8) {
                TextField("Add to the Inbox", text: $newTitle)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
                if !newTitle.isEmpty {
                    Button("Add", action: add)
                        .buttonStyle(.dtn(.primary, size: .small))
                }
                Button { model.sheet = .inboxSettings } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.ink2)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Where tasks come from")
            }
            .padding(.horizontal, 16)

            if entries.isEmpty {
                Text(model.sideList == .tasks
                     ? "No Do This Now tasks waiting. Everything else is on a day already."
                     : "Nothing waiting. Everything that passes your filters is on a day already.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                    .padding(16)
                Spacer()
            } else {
                List {
                    ForEach(entries) { entry in
                        InboxRow(entry: entry, day: day)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.line)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            Text("Drag a task onto the timeline. Drag a block back here to take it off the day.")
                .font(.caption)
                .foregroundStyle(Theme.ink3)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .background(Theme.surface2.ignoresSafeArea(edges: .bottom))
        .overlay {
            if model.blockOverSideList {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.block.opacity(0.12))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.block, lineWidth: 3)
                    Label("Let go to send it back to the Inbox", systemImage: "tray.and.arrow.down")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                        .background(Theme.surface, in: Capsule())
                }
                .padding(6)
                .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.sideListFrame = $0 }
        .onDisappear { model.sideListFrame = nil }
    }

    private func add() {
        model.addToInbox(newTitle)
        newTitle = ""
        typing = false
    }
}
