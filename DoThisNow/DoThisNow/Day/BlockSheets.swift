import SwiftUI
import DoThisNowKit

private let lengthChoices = [5, 10, 15, 20, 30, 45, 60, 90, 120]

/// An Inbox task: how long it takes, and when to do it.
struct ScheduleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let key: String
    @State private var minutes = 30
    @State private var dayOffset = 0
    @State private var time = Date()
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if let entry = model.inboxEntry(key) {
                    form(entry)
                } else {
                    ContentUnavailableView("Already planned", systemImage: "checkmark.circle",
                                           description: Text("This task is on a day now, or it’s done."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save length") { saveLength() }
                        .disabled(model.inboxEntry(key).map { $0.estimate.minutes == minutes } ?? true)
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    private var day: CalendarDay {
        model.dayShown.adding(days: dayOffset, calendar: model.calendar)
    }

    private func load() {
        guard !loaded, let entry = model.inboxEntry(key) else { return }
        loaded = true
        minutes = entry.estimate.minutes
        let firstGap = model.openSlots(on: model.dayShown, minutes: minutes, limit: 1).first ?? Int(model.state.settings.wake)
        time = model.dayShown.date(atMinute: Double(firstGap), calendar: model.calendar)
    }

    private func form(_ entry: InboxEntry) -> some View {
        let task = entry.task
        let f = model.formats
        return Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    SourceBadge(source: task.ref.source)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(Theme.display(22))
                            .foregroundStyle(Theme.ink)
                        Text([task.ref.source.label, task.listName].filter { !$0.isEmpty }.uniqued().joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(Theme.ink3)
                        if !task.notes.isEmpty {
                            Text(task.notes)
                                .font(.footnote)
                                .foregroundStyle(Theme.ink2)
                                .lineLimit(4)
                        }
                    }
                }
            }

            Section {
                ChoiceChips(options: lengthChoices.map { ($0, TimeText.duration($0)) }, selection: $minutes)
                MinuteStepper(title: "Takes", minutes: $minutes, range: 1...600)
            } header: {
                Text("How long")
            } footer: {
                if entry.estimate.basis == .custom {
                    Button("Go back to the estimate") {
                        model.setMinutes(key, nil)
                        if let fresh = model.inboxEntry(key) { minutes = fresh.estimate.minutes }
                    }
                    .font(.footnote.weight(.semibold))
                } else {
                    Text("Estimate: \(TimeText.duration(entry.estimate.minutes)), \(entry.estimate.detail). Time it on the Track tab or with the timer, and the estimate learns.")
                }
            }

            Section("When") {
                Picker("Day", selection: $dayOffset) {
                    ForEach(0..<7, id: \.self) { offset in
                        let d = model.dayShown.adding(days: offset, calendar: model.calendar)
                        Text(dayName(d)).tag(offset)
                    }
                }
                let slots = model.openSlots(on: day, minutes: minutes)
                if slots.isEmpty {
                    Text("No gap that long left on \(dayName(day).lowercased()). Pick a time below and the rest will move.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                } else {
                    ForEach(slots, id: \.self) { start in
                        Button {
                            commitLength(entry)
                            model.schedule(key, at: start, on: day, minutes: minutes)
                        } label: {
                            HStack {
                                Text(f.range(day, Double(start), Double(start + minutes)))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text("Free").font(.footnote).foregroundStyle(Theme.good)
                            }
                        }
                    }
                }
                DatePicker("Or at", selection: $time, displayedComponents: .hourAndMinute)
                Button("Put it at \(f.time(time))") {
                    commitLength(entry)
                    model.schedule(key, at: Int(model.calendar.minuteOfDay(time)), on: day, minutes: minutes)
                }
                .fontWeight(.semibold)
            }

            Section {
                Button("Done already") { model.completeEntry(key) }
                Button("Hide from the Inbox") { model.hideFromInbox(key) }
                if task.ref.source == .app {
                    Button("Edit task") { model.sheet = .editTask(task.ref.id) }
                }
            }
        }
        .tint(Theme.accent)
    }

    private func dayName(_ day: CalendarDay) -> String {
        let offset = model.today.days(until: day, calendar: model.calendar)
        if offset == 0 { return "Today" }
        if offset == 1 { return "Tomorrow" }
        return model.formats.weekdayName(day)
    }

    /// Remembers a length you changed, so the Inbox shows it too.
    private func commitLength(_ entry: InboxEntry) {
        if minutes != entry.estimate.minutes { model.setMinutes(key, minutes) }
    }

    private func saveLength() {
        model.setMinutes(key, minutes)
        dismiss()
    }
}

/// One of your blocks on the Day.
struct BlockSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let blockID: String

    var body: some View {
        NavigationStack {
            Group {
                if let block = model.state.block(blockID) {
                    content(block)
                } else {
                    ContentUnavailableView("This changed", systemImage: "calendar.badge.exclamationmark",
                                           description: Text("It’s no longer on the day."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func content(_ block: TimeBlock) -> some View {
        let f = model.formats
        let isToday = block.day == model.today
        let task = block.ref.source == .app ? model.state.task(block.ref.id) : nil
        let estimate = model.state.estimate(title: block.title)

        return List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(block.title)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.ink)
                        .strikethrough(block.done)
                    Text("\(f.range(block.day, Double(block.start), Double(block.end))) · from \(block.ref.source.label)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                    if estimate.isFromHistory {
                        Text("Usually takes \(TimeText.duration(estimate.minutes)) (\(estimate.detail))")
                            .font(.footnote)
                            .foregroundStyle(Theme.ink3)
                    }
                }
            }
            if !block.done {
                Section {
                    MinuteStepper(title: "Takes", minutes: Binding(
                        get: { model.state.block(blockID)?.minutes ?? block.minutes },
                        set: { model.setBlockMinutes(blockID, $0) }
                    ), range: 5...600)
                    DatePicker("Starts", selection: Binding(
                        get: { block.day.date(atMinute: Double(model.state.block(blockID)?.start ?? block.start), calendar: model.calendar) },
                        set: { model.moveBlock(blockID, to: Int(model.calendar.minuteOfDay($0))) }
                    ), displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Anything it runs into moves out of the way.")
                }
            }
            Section {
                if block.done {
                    option("Not done after all", detail: "Puts it back on the plan") { model.reopenBlock(blockID) }
                } else {
                    if isToday && model.state.active == nil {
                        option("Start the timer", detail: "Times it, so the next estimate learns from it") {
                            model.startBlock(blockID)
                        }
                    }
                    option("Done", detail: block.ref.source == .app ? "Crosses it off" : "Ticks it off in \(block.ref.source.label) too") {
                        model.completeBlock(blockID)
                    }
                    option("Back to the Inbox", detail: "Off the day, still to do") { model.unschedule(blockID) }
                }
                if let task {
                    option("Edit task", detail: nil) { model.sheet = .editTask(task.id) }
                }
            }
        }
    }

    private func option(_ title: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.bold)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(Theme.ink3)
                }
            }
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
