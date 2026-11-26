import SwiftUI
import UIKit
import LittlesKit

/// What a log sheet is opened for: a new entry of a kind, or an existing one.
struct LogTarget: Identifiable {
    var entry: LogEntry
    var isNew: Bool
    var id: String { entry.id }
}

/// The Today tab: running timers, "how long since", one-tap logging, the
/// day's totals and its timeline, for the chosen kid.
struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @State private var day = Date()
    @State private var target: LogTarget?
    @State private var showFamily = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        KidPicker(selection: Binding(get: { model.kidID }, set: { model.select($0) }))
                            .padding(.horizontal, -16)
                        if let kid = model.kid {
                            content(kid: kid, now: context.date)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).month().day()))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 2) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("Previous day")
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(isToday)
                            .accessibilityLabel("Next day")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFamily = true } label: { Image(systemName: "person.2.fill") }
                        .accessibilityLabel("Family and settings")
                }
            }
            .sheet(item: $target) { target in
                LogSheet(entry: target.entry, isNew: target.isNew)
                    .environmentObject(model)
            }
            .sheet(isPresented: $showFamily) {
                FamilyView().environmentObject(model)
            }
            .onAppear(perform: openScreenshotSheet)
        }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(day)
    }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
    }

    @ViewBuilder
    private func content(kid: Kid, now: Date) -> some View {
        let logs = model.state.logs
        let running = Summary.running(logs, kidID: kid.id)
        if isToday {
            ForEach(running) { entry in
                RunningCard(entry: entry, kid: kid, now: now)
            }
            SinceRow(kid: kid, now: now)
            CountdownCard(kid: kid, now: now)
            MedicineCard(kid: kid, now: now)
            SickCard(kid: kid, now: now)
            NapCard(kid: kid, now: now)
            PottyCard(kid: kid)
            ChartsRow(kid: kid)
        }
        QuickLogGrid(kid: kid) { kind in quickLog(kind, kid: kid) }
        DayTotalsCard(kid: kid, day: day, now: now)
        if isToday, let next = nextUp(kid: kid, now: now) {
            NextUpCard(day: next.day, entry: next.entry)
        }
        SectionTitle(text: isToday ? "Today's log" : "Log")
        let entries = Summary.timeline(logs, kidID: kid.id, on: day)
        if entries.isEmpty {
            EmptyNote(emoji: kid.emoji.isEmpty ? "📝" : kid.emoji, text: "Nothing logged yet. Tap a button above to add the first thing.")
                .card()
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    TimelineRow(entry: entry, now: now, units: model.units, photo: model.photo(entry.photo))
                        .contentShape(Rectangle())
                        .onTapGesture { target = LogTarget(entry: entry, isNew: false) }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { target = LogTarget(entry: entry, isNew: false) }
                            if entry.isRunning {
                                Button("Stop now", systemImage: "stop.fill") { model.stop(entry.id) }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) { model.deleteLog(entry.id) }
                        }
                    if entry.id != entries.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .card()
        }
    }

    private func nextUp(kid: Kid, now: Date) -> (day: String, entry: AgendaEntry)? {
        var only = model.state
        only.routines = only.routines.filter { $0.kidIDs.isEmpty || $0.kidIDs.contains(kid.id) }
        only.events = only.events.filter { $0.kidIDs.isEmpty || $0.kidIDs.contains(kid.id) }
        guard let next = Agenda.next(after: now, state: only) else { return nil }
        // Only today and tomorrow are worth a card here.
        return next.day <= Dates.addDays(Dates.key(now), 1) ? next : nil
    }

    /// A tap on a quick-log button. Sleep toggles its timer; the rest open a sheet.
    private func quickLog(_ kind: LogKind, kid: Kid) {
        let when = logTime()
        switch kind {
        case .sleep where isToday:
            if let running = Summary.running(model.state.logs, kidID: kid.id).first(where: { $0.kind == .sleep }) {
                model.stop(running.id)
            } else {
                model.start(.sleep, kidID: kid.id)
            }
        default:
            var entry = LogEntry(kidID: kid.id, kind: kind, start: when)
            prefill(&entry, kid: kid)
            target = LogTarget(entry: entry, isNew: true)
        }
    }

    /// Now on today; noon on another day.
    private func logTime() -> Date {
        if isToday { return Date() }
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    /// Sensible starting values, copied from the last entry of the same kind.
    private func prefill(_ entry: inout LogEntry, kid: Kid) {
        let last = Summary.last(model.state.logs, kidID: kid.id, kinds: [entry.kind])
        switch entry.kind {
        case .bottle:
            entry.amountOz = last?.amountOz ?? 4
            entry.milk = last?.milk ?? (kid.ageMonths(on: Date()) >= 12 ? .wholeMilk : .formula)
        case .pump:
            entry.amountOz = last?.amountOz ?? 3
        case .nursing:
            entry.side = Summary.nextSide(model.state.logs, kidID: kid.id)
            entry.end = entry.start
        case .diaper:
            entry.diaper = .wet
        case .potty:
            entry.potty = .pee
        case .meds:
            entry.medicine = last?.medicine ?? ""
            entry.dose = last?.dose ?? ""
        case .temperature:
            entry.temperatureF = 98.6
        case .sleep:
            entry.end = entry.start.addingTimeInterval(3600)
            entry.start = entry.start.addingTimeInterval(-3600)
        case .screen, .outside:
            entry.minutes = 30
        case .growth:
            let latest = Summary.growth(model.state.logs, kidID: kid.id).last
            entry.weightLb = latest?.weightLb
            entry.heightIn = latest?.heightIn
            entry.headIn = latest?.headIn
        default:
            break
        }
    }

    private func openScreenshotSheet() {
        guard let kid = model.kid else { return }
        if Screenshots.shows("bottle") {
            var entry = LogEntry(kidID: kid.id, kind: .bottle, start: Date())
            prefill(&entry, kid: kid)
            target = LogTarget(entry: entry, isNew: true)
        } else if Screenshots.shows("meal") {
            let entry = LogEntry(kidID: kid.id, kind: .solids, start: Date(),
                                 bites: [FoodBite(foodID: "salmon", liking: .loved), FoodBite(foodID: "sweetpotato"),
                                         FoodBite(foodID: "blueberry", liking: .meh)])
            target = LogTarget(entry: entry, isNew: true)
        } else if Screenshots.shows("family") {
            showFamily = true
        }
    }
}

/// A sleep or nursing timer that's running, with a big Stop button.
struct RunningCard: View {
    @EnvironmentObject var model: AppModel
    let entry: LogEntry
    let kid: Kid
    let now: Date

    var body: some View {
        HStack(spacing: 14) {
            Text(entry.kind.emoji).font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind == .sleep ? "\(kid.name) is asleep" : "Nursing" + (entry.side.map { " · \($0.title)" } ?? ""))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(Dates.duration(entry.duration(now: now))) · since \(entry.start.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            if entry.kind == .nursing {
                Button {
                    let next: Side = entry.side == .left ? .right : .left
                    model.stop(entry.id)
                    model.start(.nursing, kidID: kid.id, side: next)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.2), in: Circle())
                }
                .accessibilityLabel("Switch side")
            }
            Button {
                model.stop(entry.id)
            } label: {
                Text(entry.kind == .sleep ? "Awake" : "Stop")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
                    .foregroundStyle(Theme.color(kid))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Theme.color(kid).gradient, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// "Fed 2h ago · Diaper 40m ago · Awake 1h 10m", or the toddler version.
struct SinceRow: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    let now: Date

    var body: some View {
        let logs = model.state.logs
        let age = kid.ageMonths(on: now)
        HStack(spacing: 10) {
            if age < 18 {
                let feed = Summary.last(logs, kidID: kid.id, kinds: [.bottle, .nursing])
                let next = Summary.nextFeed(logs, kidID: kid.id, now: now)
                tile("🍼", "Last feed", ago(feed?.start),
                     next.map { $0 > now ? "next ~\($0.formatted(date: .omitted, time: .shortened))" : "due now" })
                tile("🧷", "Last diaper", ago(Summary.last(logs, kidID: kid.id, kinds: [.diaper])?.start), nil)
            } else {
                tile("🍽️", "Last meal", ago(Summary.last(logs, kidID: kid.id, kinds: [.solids])?.start), nil)
                tile("🚽", "Last potty", ago(Summary.last(logs, kidID: kid.id, kinds: [.potty, .diaper])?.start), nil)
            }
            sleepTile(logs)
        }
    }

    private func sleepTile(_ logs: [LogEntry]) -> some View {
        let last = Summary.last(logs, kidID: kid.id, kinds: [.sleep])
        if let last, last.isRunning {
            return tile("😴", "Asleep", Dates.duration(last.duration(now: now)), nil)
        }
        if let end = last?.end {
            return tile("🌤️", "Awake", Dates.duration(now.timeIntervalSince(end)), nil)
        }
        return tile("😴", "Last sleep", "—", nil)
    }

    private func ago(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Dates.duration(now.timeIntervalSince(date)) + " ago"
    }

    private func tile(_ emoji: String, _ title: String, _ value: String, _ footnote: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(emoji) \(title)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(Theme.display(17))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let footnote {
                Text(footnote)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

/// The one-tap buttons, ordered for the kid's age.
struct QuickLogGrid: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    let onTap: (LogKind) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        let kinds = Summary.quickKinds(ageMonths: kid.ageMonths(on: Date()))
        let sleeping = Summary.running(model.state.logs, kidID: kid.id).contains { $0.kind == .sleep }
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(kinds) { kind in
                Button { onTap(kind) } label: {
                    VStack(spacing: 4) {
                        Text(kind.emoji).font(.system(size: 26))
                        Text(kind == .sleep && sleeping ? "Wake" : kind.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind == .sleep ? (sleeping ? "Wake up" : "Start sleep") : "Log \(kind.title)")
            }
        }
    }
}

/// The day's totals in one card.
struct DayTotalsCard: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    let day: Date
    let now: Date

    var body: some View {
        let s = Summary.day(model.state.logs, kidID: kid.id, on: day, now: now)
        let items = stats(s)
        VStack(alignment: .leading, spacing: 10) {
            Text("Totals")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.muted)
            if items.isEmpty {
                Text("Nothing yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.value)
                                .font(Theme.display(18))
                                .foregroundStyle(Theme.ink)
                            Text(item.label)
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
        }
        .card()
    }

    private struct Stat: Identifiable {
        var label: String
        var value: String
        var id: String { label }
    }

    private func stats(_ s: DaySummary) -> [Stat] {
        var items: [Stat] = []
        if s.bottles > 0 { items.append(Stat(label: "\(s.bottles) bottle\(s.bottles == 1 ? "" : "s")", value: model.units.volume(s.bottleOz))) }
        if s.nursing > 0 { items.append(Stat(label: "nursing ×\(s.nursing)", value: "\(s.nursingMinutes)m")) }
        if s.diapers > 0 { items.append(Stat(label: "diapers · \(s.dirty) dirty", value: "\(s.diapers)")) }
        if s.sleepMinutes > 0 { items.append(Stat(label: "sleep · \(s.naps) nap\(s.naps == 1 ? "" : "s")", value: Dates.duration(Double(s.sleepMinutes) * 60))) }
        if s.meals > 0 { items.append(Stat(label: "meals · \(s.foods) foods", value: "\(s.meals)")) }
        if s.pottySuccesses + s.accidents > 0 { items.append(Stat(label: "potty · \(s.accidents) accident\(s.accidents == 1 ? "" : "s")", value: "\(s.pottySuccesses)")) }
        return items
    }
}

/// The next thing on the schedule for this kid.
struct NextUpCard: View {
    @EnvironmentObject var model: AppModel
    let day: String
    let entry: AgendaEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.emoji).font(.system(size: 28))
            VStack(alignment: .leading, spacing: 2) {
                Text("Next up" + (day == Dates.key(Date()) ? "" : " tomorrow"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(entry.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if let start = entry.start {
                    Text(Dates.clock(start) + (entry.place.isEmpty ? "" : " · \(entry.place)"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
        }
        .card()
    }
}

/// One line of the day's log.
struct TimelineRow: View {
    let entry: LogEntry
    let now: Date
    var units: Units = .us
    var photo: UIImage? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.kind.emoji)
                .font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(Theme.sunk, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.kind.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    if entry.bites.contains(where: { $0.reaction }) {
                        Pill(text: "Reaction", color: Theme.warn)
                    }
                    Spacer()
                    Text(timeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
                let detail = entry.detail(now: now, units: units)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 8)
    }

    private var timeLabel: String {
        let start = entry.start.formatted(date: .omitted, time: .shortened)
        if entry.kind.isTimed, let end = entry.end {
            return start + "–" + end.formatted(date: .omitted, time: .shortened)
        }
        return start
    }
}
