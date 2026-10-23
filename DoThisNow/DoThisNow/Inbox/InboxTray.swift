import SwiftUI
import DoThisNowKit

/// The drawer under the Day timeline: tasks from every source, each with
/// how long it should take. Drag one onto the timeline, or tap it.
struct InboxTray: View {
    @Environment(AppModel.self) private var model
    let day: CalendarDay
    @State private var newTitle = ""
    @FocusState private var typing: Bool

    var body: some View {
        let entries = model.inboxEntries
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.line)
                .frame(width: 36, height: 5)
                .padding(.top, 7)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.inboxOpen.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.full.fill")
                            .foregroundStyle(Theme.block)
                        Text("Inbox")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text("\(entries.count)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(Theme.ink3)
                        Image(systemName: model.inboxOpen ? "chevron.down" : "chevron.up")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.ink3)
                    }
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Inbox, \(entries.count) task\(entries.count == 1 ? "" : "s")")
                .accessibilityHint(model.inboxOpen ? "Closes the Inbox" : "Opens the Inbox")
                Spacer()
                Button { model.sheet = .inboxSettings } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.ink2)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Where tasks come from")
            }
            .padding(.horizontal, 16)

            if model.inboxOpen {
                VStack(alignment: .leading, spacing: 8) {
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
                    }
                    .padding(.horizontal, 16)

                    if entries.isEmpty {
                        Text(model.state.inbox.reminders.on || model.state.inbox.google.on
                             ? "Nothing waiting. Everything that passes your filters is on a day already."
                             : "Nothing waiting. Type something above, or bring in Reminders or Google Tasks with the filter button.")
                            .font(.footnote)
                            .foregroundStyle(Theme.ink2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
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
                        .frame(height: min(290, CGFloat(entries.count) * 62 + 4))
                    }
                    Text("Touch and hold a task, then drag it onto the timeline. Or tap it to pick a time.")
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18, style: .continuous)
                .fill(Theme.surface2)
                .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func add() {
        model.addToInbox(newTitle)
        newTitle = ""
        typing = false
    }
}

private struct InboxRow: View {
    @Environment(AppModel.self) private var model
    let entry: InboxEntry
    let day: CalendarDay

    var body: some View {
        let task = entry.task
        HStack(spacing: 12) {
            SourceBadge(source: task.ref.source)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            EstimateChip(estimate: entry.estimate)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .onTapGesture { model.sheet = .schedule(entry.id) }
        .draggable(entry.id) {
            HStack(spacing: 8) {
                Text(task.title).font(.subheadline.weight(.bold)).lineLimit(1)
                Text(TimeText.duration(entry.estimate.minutes)).font(.caption)
            }
            .foregroundStyle(Theme.blockInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.block, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .swipeActions(edge: .leading) {
            Button("Done") { model.completeEntry(entry.id) }
                .tint(Theme.good)
        }
        .swipeActions(edge: .trailing) {
            Button("Hide") { model.hideFromInbox(entry.id) }
                .tint(Theme.ink3)
            Button("Next gap") { model.scheduleInNextGap(entry.id, on: day) }
                .tint(Theme.block)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens times for it. Or drag it onto the timeline.")
        .accessibilityAction(named: "Done") { model.completeEntry(entry.id) }
        .accessibilityAction(named: "Hide from the Inbox") { model.hideFromInbox(entry.id) }
    }

    private var detail: String {
        let task = entry.task
        var parts: [String] = []
        if task.ref.source == .inbox {
            if !task.notes.isEmpty { parts.append(task.notes.replacingOccurrences(of: "\n", with: " ")) }
        } else if !task.listName.isEmpty {
            parts.append(task.listName)
        }
        if let due = task.due {
            parts.insert(model.engine.deadlineLabel(CalendarDay(due, calendar: model.calendar)), at: 0)
        }
        return parts.isEmpty ? task.ref.source.label : parts.joined(separator: " · ")
    }
}

/// A small icon for where a task came from.
struct SourceBadge: View {
    let source: TaskSource

    var body: some View {
        Image(systemName: symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.ink2)
            .frame(width: 30, height: 30)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(source.label)
    }

    private var symbol: String {
        switch source {
        case .app: return "bolt.fill"
        case .reminders: return "checklist"
        case .google: return "g.circle"
        case .inbox: return "tray.and.arrow.down"
        }
    }
}

/// "~13m", with a stopwatch when it comes from your own timings.
struct EstimateChip: View {
    let estimate: Estimate

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: estimate.isFromHistory ? "stopwatch" : estimate.basis == .custom ? "pencil" : "clock")
                .font(.caption2.weight(.bold))
            Text(TimeText.duration(estimate.minutes))
                .font(.caption.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(Theme.ink2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surface, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("About \(TimeText.duration(estimate.minutes)), \(estimate.detail)")
    }
}
