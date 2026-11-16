import SwiftUI
import DoThisNowKit

/// The "To place" row at the top of a day: tasks sent to this day with no
/// time yet. Drag one onto the timeline to give it a time, or tap it to pick
/// one. Touch and hold for more. Hidden when nothing is waiting.
struct DayQueueRow: View {
    @Environment(AppModel.self) private var model
    let day: CalendarDay

    var body: some View {
        let entries = model.queued(on: day)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .foregroundStyle(Theme.block)
                    Text("To place")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("\(entries.count)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.ink3)
                    Spacer(minLength: 4)
                    Text("Drag onto the timeline")
                        .font(.caption)
                        .foregroundStyle(Theme.ink3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                // Wraps instead of scrolling sideways, so a sideways swipe still changes the day.
                FlowLayout(spacing: 8) {
                    ForEach(entries) { entry in
                        QueueChip(entry: entry, day: day)
                    }
                }
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.block.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
    }
}

private struct QueueChip: View {
    @Environment(AppModel.self) private var model
    let entry: InboxEntry
    let day: CalendarDay

    var body: some View {
        let task = entry.task
        HStack(spacing: 6) {
            Text(task.title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Text(TimeText.duration(entry.estimate.minutes))
                .font(.caption2)
                .opacity(0.8)
        }
        .foregroundStyle(Theme.blockInk)
        .padding(.horizontal, 11)
        .frame(minHeight: 34)
        .frame(maxWidth: 260)
        .background(Theme.block, in: Capsule())
        .contentShape(Capsule())
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
        .contextMenu {
            Button { model.scheduleInNextGap(entry.id, on: day) } label: {
                Label("Put in the next gap", systemImage: "arrow.down.to.line")
            }
            Button { model.sheet = .sendToDay(entry.id) } label: {
                Label("Send to another day", systemImage: "calendar")
            }
            Button { model.unqueue(entry.id) } label: {
                Label("Back to the Inbox", systemImage: "tray")
            }
            Button { model.completeEntry(entry.id) } label: {
                Label("Done", systemImage: "checkmark")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens times for it. Or drag it onto the timeline.")
        .accessibilityAction(named: "Put in the next gap") { model.scheduleInNextGap(entry.id, on: day) }
        .accessibilityAction(named: "Send to another day") { model.sheet = .sendToDay(entry.id) }
        .accessibilityAction(named: "Back to the Inbox") { model.unqueue(entry.id) }
    }
}

/// Touch and hold a task, then pick a day: two weeks as Monday-first strips.
/// The task waits at the top of that day with no time.
struct SendToDaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let key: String

    var body: some View {
        NavigationStack {
            Group {
                if let entry = model.inboxEntry(key) {
                    content(entry)
                } else {
                    ContentUnavailableView("Already planned", systemImage: "checkmark.circle",
                                           description: Text("This task is on a day now, or it’s done."))
                }
            }
            .navigationTitle("Send to a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(380), .large])
    }

    private func content(_ entry: InboxEntry) -> some View {
        let first = model.weekStart(of: model.today)
        let weeks = (0..<3).map { first.adding(days: 7 * $0, calendar: model.calendar) }
            .filter { $0 <= model.lastDayAhead }
        let current = model.state.queuedDay(for: key)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.task.title)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text("It waits at the top of that day until you drag it to a time.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                }
                ForEach(weeks, id: \.self) { monday in
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { offset in
                            let day = monday.adding(days: offset, calendar: model.calendar)
                            dayCell(day, current: current)
                        }
                    }
                }
                if current != nil {
                    Button("Back to the Inbox") {
                        model.unqueue(key)
                        dismiss()
                    }
                    .buttonStyle(.dtn(size: .small))
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
    }

    private func dayCell(_ day: CalendarDay, current: CalendarDay?) -> some View {
        let calendar = model.calendar
        let open = model.canShow(day)
        let isToday = day == model.today
        let chosen = day == current
        let waiting = model.state.queue(on: day).count
        let symbols = calendar.veryShortWeekdaySymbols
        let index = day.weekdayIndex(calendar: calendar)
        let name = isToday ? "Today" : day == model.today.adding(days: 1, calendar: calendar) ? "Tomorrow" : model.formats.weekdayName(day)

        return Button { model.sendToDay(key, day) } label: {
            VStack(spacing: 3) {
                Text(symbols.indices.contains(index) ? symbols[index] : "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isToday ? Theme.accent : Theme.ink3)
                Text("\(day.day)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(chosen ? Theme.blockInk : Theme.ink)
                Text(waiting > 0 ? "\(waiting)" : " ")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(chosen ? Theme.blockInk : Theme.block)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(chosen ? Theme.block : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isToday ? Theme.accent : Theme.line, lineWidth: isToday ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .opacity(open ? 1 : 0.35)
        .accessibilityLabel("\(name), \(model.formats.shortDate(day))\(waiting > 0 ? ", \(waiting) waiting" : "")")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
