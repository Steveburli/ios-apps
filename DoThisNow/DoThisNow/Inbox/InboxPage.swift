import SwiftUI
import DoThisNowKit

/// The Inbox as its own page on the Day tab: tap tasks to pick them, then put
/// them all on the day at once, each in the first gap that fits.
struct InboxPage: View {
    @Environment(AppModel.self) private var model
    let day: CalendarDay
    @State private var picked: Set<String> = []
    @State private var newTitle = ""
    @FocusState private var typing: Bool

    var body: some View {
        let entries = model.inboxEntries
        let chosen = entries.map(\.id).filter(picked.contains)
        let offset = model.today.days(until: day, calendar: model.calendar)
        let dayName = offset == 0 ? "today" : offset == 1 ? "tomorrow" : model.formats.weekdayName(day)

        List {
            Section {
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
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } footer: {
                Text(entries.isEmpty
                     ? "Nothing waiting. Everything that passes your filters is on a day already."
                     : "Tap tasks to pick them, then put them on \(dayName). Each one goes in the first gap that fits.")
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
            }
            ForEach(entries) { entry in
                PickRow(entry: entry, picked: picked.contains(entry.id)) {
                    if picked.contains(entry.id) { picked.remove(entry.id) } else { picked.insert(entry.id) }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Theme.line)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !chosen.isEmpty {
                HStack(spacing: 10) {
                    Button("Clear") { picked = [] }
                        .buttonStyle(.dtn(size: .small))
                    Button("Put \(chosen.count) on \(dayName)") {
                        model.scheduleInNextGaps(chosen, on: day)
                        picked = []
                    }
                    .buttonStyle(.dtn(.primary))
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.surface2.ignoresSafeArea(edges: .bottom))
            }
        }
    }

    private func add() {
        model.addToInbox(newTitle)
        newTitle = ""
        typing = false
    }
}

private struct PickRow: View {
    @Environment(AppModel.self) private var model
    let entry: InboxEntry
    let picked: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(picked ? Theme.block : Theme.ink3)
            SourceBadge(source: entry.task.ref.source)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if !entry.task.listName.isEmpty {
                    Text(entry.task.listName)
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            EstimateChip(estimate: entry.estimate)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .swipeActions(edge: .leading) {
            Button("Done") { model.completeEntry(entry.id) }
                .tint(Theme.good)
        }
        .swipeActions(edge: .trailing) {
            Button("Hide") { model.hideFromInbox(entry.id) }
                .tint(Theme.ink3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Done") { model.completeEntry(entry.id) }
        .accessibilityAction(named: "Hide from the Inbox") { model.hideFromInbox(entry.id) }
    }
}
