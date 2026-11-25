import SwiftUI
import LittlesKit

/// The Schedule tab: a week strip, the chosen day's routines and events for
/// both kids, that day's pack list, and the weekly routines to edit.
struct ScheduleView: View {
    @EnvironmentObject var model: AppModel
    @State private var day = Dates.key(Date())
    @State private var editingRoutine: RoutineItem?
    @State private var editingEvent: OneOffEvent?
    @State private var editingPack: PackItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WeekStrip(day: $day)
                    agenda
                    packList
                    routines
                    packItems
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Weekly routine", systemImage: "repeat") {
                            editingRoutine = RoutineItem(title: "", weekdays: [2, 3, 4, 5, 6], start: 8 * 60, kind: .school)
                        }
                        Button("One-day event", systemImage: "calendar.badge.plus") {
                            editingEvent = OneOffEvent(title: "", day: day, kind: .special)
                        }
                        Button("Something to pack", systemImage: "backpack.fill") {
                            editingPack = PackItem(title: "", kidID: model.state.kids.last?.id ?? "")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(item: $editingRoutine) { item in
                RoutineEditor(item: item, isNew: !model.state.routines.contains { $0.id == item.id })
                    .environmentObject(model)
            }
            .sheet(item: $editingEvent) { event in
                EventEditor(event: event, isNew: !model.state.events.contains { $0.id == event.id })
                    .environmentObject(model)
            }
            .sheet(item: $editingPack) { item in
                PackItemEditor(item: item, isNew: !model.state.packItems.contains { $0.id == item.id })
                    .environmentObject(model)
            }
        }
    }

    private var dayTitle: String {
        let today = Dates.key(Date())
        if day == today { return "Today" }
        if day == Dates.addDays(today, 1) { return "Tomorrow" }
        return Dates.date(day)?.formatted(.dateTime.weekday(.wide).month().day()) ?? day
    }

    private var agenda: some View {
        let entries = Agenda.entries(on: day, state: model.state)
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: dayTitle)
            if entries.isEmpty {
                EmptyNote(emoji: "🌈", text: "Nothing planned. Add preschool days, classes and naps with +.").card()
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        AgendaRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { edit(entry) }
                        if entry.id != entries.last?.id { Divider().padding(.leading, 70) }
                    }
                }
                .card()
            }
        }
    }

    @ViewBuilder
    private var packList: some View {
        let lines = Agenda.packList(on: day, state: model.state)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("🎒 Pack for \(dayTitle.lowercased() == "today" ? "today" : dayTitle)")
                        .font(.headline)
                    Spacer()
                    Text("\(lines.filter { $0.packed }.count)/\(lines.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(lines) { line in
                    Button {
                        model.togglePacked(day: day, id: line.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: line.packed ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(line.packed ? Theme.good : Theme.line)
                            Text(line.title)
                                .strikethrough(line.packed)
                                .foregroundStyle(line.packed ? Theme.muted : Theme.ink)
                            Spacer()
                            if let kidID = line.kidID, let kid = model.kid(kidID), model.state.kids.count > 1 {
                                KidBadge(kid: kid, size: 22)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    private var routines: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Every week")
            if model.state.routines.isEmpty {
                EmptyNote(emoji: "🏫", text: "Add preschool hours, drop-off and pickup, classes and naps. Pickup can remind you ahead of time.").card()
            } else {
                VStack(spacing: 0) {
                    let sorted = model.state.routines.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
                    ForEach(sorted) { item in
                        Button { editingRoutine = item } label: {
                            HStack(spacing: 12) {
                                Text(item.kind.emoji).font(.title3).frame(width: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                                    Text("\(item.daysLabel) · \(Dates.clock(item.start))" + (item.end.map { "–" + Dates.clock($0) } ?? "")
                                         + " · " + model.names(item.kidIDs))
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if item.remind != nil {
                                    Image(systemName: "bell.fill").font(.caption).foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if item.id != sorted.last?.id { Divider().padding(.leading, 46) }
                    }
                }
                .card()
            }
        }
    }

    @ViewBuilder
    private var packItems: some View {
        if !model.state.packItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Pack list")
                VStack(spacing: 0) {
                    ForEach(model.state.packItems) { item in
                        Button { editingPack = item } label: {
                            HStack {
                                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text((model.kid(item.kidID)?.name ?? "") + " · "
                                     + (item.weekdays.isEmpty ? "school days" : item.weekdays.map { Dates.shortWeekdays[$0 - 1] }.joined(separator: ", ")))
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
        }
    }

    private func edit(_ entry: AgendaEntry) {
        if entry.isEvent {
            editingEvent = model.state.events.first { $0.id == entry.id }
        } else {
            editingRoutine = model.state.routines.first { $0.id == entry.id }
        }
    }
}

/// Seven days, Sunday to Saturday, with dots for days that have events.
struct WeekStrip: View {
    @EnvironmentObject var model: AppModel
    @Binding var day: String
    @State private var weekOffset = 0

    var body: some View {
        let today = Dates.key(Date())
        let start = Dates.addDays(today, -(Dates.weekday(today) - 1) + weekOffset * 7)
        let days = (0..<7).map { Dates.addDays(start, $0) }
        HStack(spacing: 4) {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous week")
            ForEach(days, id: \.self) { key in
                let selected = key == day
                let hasEvent = model.state.events.contains { $0.day == key }
                Button { day = key } label: {
                    VStack(spacing: 3) {
                        Text(Dates.letterWeekdays[Dates.weekday(key) - 1])
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.muted)
                        Text(String(Int(key.suffix(2)) ?? 0))
                            .font(Theme.display(17))
                            .foregroundStyle(selected ? Color.white : (key == today ? Theme.accent : Theme.ink))
                        Circle()
                            .fill(hasEvent ? (selected ? Color.white : Theme.warn) : Color.clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(selected ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next week")
        }
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

struct AgendaRow: View {
    @EnvironmentObject var model: AppModel
    let entry: AgendaEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                if let start = entry.start {
                    Text(Dates.clock(start)).font(.caption.weight(.bold)).foregroundStyle(Theme.ink)
                    if let end = entry.end {
                        Text(Dates.clock(end)).font(.caption2).foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("All day").font(.caption.weight(.bold)).foregroundStyle(Theme.warn)
                }
            }
            .frame(width: 58, alignment: .trailing)
            Text(entry.emoji).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.bold))
                    .strikethrough(entry.cancelled)
                    .foregroundStyle(entry.cancelled ? Theme.muted : Theme.ink)
                let detail = [entry.place, entry.note].filter { !$0.isEmpty }.joined(separator: " · ")
                if entry.cancelled {
                    Text("No school today").font(.caption).foregroundStyle(Theme.warn)
                } else if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: -6) {
                ForEach(kids) { kid in KidBadge(kid: kid, size: 22) }
            }
        }
        .padding(.vertical, 8)
    }

    private var kids: [Kid] {
        entry.kidIDs.isEmpty ? model.state.kids : entry.kidIDs.compactMap { model.kid($0) }
    }
}
