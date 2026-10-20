import SwiftUI
import DoThisNowKit

/// The day planner: work is a rock, tasks are soft, events are jelly with a
/// hard core, and sleep moves but complains.
struct DayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        let day = model.dayShown
        let plan = engine.planDay(day)
        let offset = model.today.days(until: day, calendar: model.calendar)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(day: day, offset: offset)
                    stats(plan)
                    fixes(plan)
                    legend
                    DayTimeline(plan: plan, engine: engine)
                    lists(plan, offset: offset)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 32)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .onAppear { scrollToNow(proxy) }
            .onChange(of: model.scrollDayToNow) { scrollToNow(proxy) }
        }
    }

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        guard model.scrollDayToNow else { return }
        model.scrollDayToNow = false
        DispatchQueue.main.async {
            proxy.scrollTo(DayTimeline.nowID, anchor: UnitPoint(x: 0.5, y: 0.35))
        }
    }

    private func header(day: CalendarDay, offset: Int) -> some View {
        let name = offset == 0 ? "Today" : offset == 1 ? "Tomorrow" : model.formats.weekdayName(day)
        return HStack(spacing: 6) {
            Button { model.showDay(offset: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 40)
            }
            .disabled(offset <= 0)
            .accessibilityLabel("Previous day")
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.ink)
                Text(model.formats.shortDate(day))
                    .font(.footnote)
                    .foregroundStyle(Theme.ink3)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Button { model.showDay(offset: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 40)
            }
            .disabled(offset >= 13)
            .accessibilityLabel("Next day")
            Spacer()
            Button("+ Event") { model.sheet = .newEvent(day) }
                .buttonStyle(.dtn())
        }
        .foregroundStyle(Theme.ink2)
    }

    private func stats(_ plan: DayPlan) -> some View {
        let f = model.formats
        var cards: [(tone: StatCard.Tone, title: String, detail: String)] = []
        if plan.push > 0 {
            cards.append((.bad, "Bedtime pushed to \(f.time(plan.day, plan.sleepStart))",
                          "\(TimeText.duration(plan.push)) past your \(f.time(plan.day, plan.bed)) bedtime"))
        } else {
            cards.append((.good, "In bed by \(f.time(plan.day, plan.bed))",
                          plan.free >= 15 ? "\(TimeText.duration(plan.free)) of breathing room" : "Packed, but it fits"))
        }
        let ghostEvents = plan.ghostEvents.count
        if ghostEvents > 0 {
            cards.append((.warn, "\(ghostEvents) event\(ghostEvents > 1 ? "s" : "") can’t happen", "Shown as dashed ghosts. Tap one to fix it."))
        }
        if !plan.ghosts.isEmpty {
            cards.append((.warn, "\(plan.ghosts.count) thing\(plan.ghosts.count > 1 ? "s" : "") won’t fit", "Listed below the timeline"))
        }
        if plan.level >= 1 && plan.live.contains(where: \.squeezed) {
            cards.append((.warn, "Leaving events early", "Your events got squeezed to make room"))
        }
        if plan.level >= 2 {
            cards.append((.bad, "Tasks are crashing", "Squeezed to 70% to fit. Drop something?"))
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                StatCard(tone: card.tone, title: card.title, detail: card.detail)
            }
        }
    }

    @ViewBuilder
    private func fixes(_ plan: DayPlan) -> some View {
        let current = plan.mealMode.minutes
        let faster = DinnerMode.allCases.filter { $0.minutes > 0 && $0.minutes < current }
        if plan.meal != nil && plan.push > 0 && !faster.isEmpty {
            FlowLayout {
                Text("Get time back:")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
                    .padding(.vertical, 8)
                ForEach(faster, id: \.self) { mode in
                    Button("\(mode.label) (saves \(TimeText.duration(current - mode.minutes)))") { model.setDinner(mode) }
                        .buttonStyle(.dtn(size: .small))
                }
            }
        }
    }

    private var legend: some View {
        FlowLayout(spacing: 10) {
            LegendItem(text: "Work: a rock, can’t move") { RoundedRectangle(cornerRadius: 4).fill(Theme.rock) }
            LegendItem(text: "Tasks: soft, they flow around") { RoundedRectangle(cornerRadius: 7).fill(Theme.soft) }
            LegendItem(text: "Events: drag the solid part to pick when you arrive") { RoundedRectangle(cornerRadius: 4).fill(Theme.core) }
            LegendItem(text: "Jelly: extra time at the event, squeezable") {
                RoundedRectangle(cornerRadius: 4).fill(Theme.jelly).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.jellyLine, lineWidth: 1.5))
            }
            LegendItem(text: "Sleep: moves, but complains") { RoundedRectangle(cornerRadius: 4).fill(Theme.sleep) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func lists(_ plan: DayPlan, offset: Int) -> some View {
        let f = model.formats
        let which = offset == 0 ? "today" : "this day"
        let events = model.state.events.filter { $0.day == plan.day }.sorted { $0.start < $1.start }
        let skipped = model.state.dayConfig(plan.day).skip.compactMap { model.state.task($0) }.filter(\.isActive)

        VStack(alignment: .leading, spacing: 18) {
            if !plan.ghosts.isEmpty {
                ListSection(title: "Won’t fit \(which)") {
                    ForEach(plan.ghosts, id: \.chunk.id) { ghost in
                        PlainListRow(title: ghost.chunk.title, detail: "\(TimeText.duration(ghost.short)) short") {
                            Button("Options") { model.sheet = .dayItem(ghost.chunk.id) }
                                .buttonStyle(.dtn(size: .small))
                        }
                    }
                }
            }
            ListSection(title: "Events") {
                if events.isEmpty {
                    Text("No events. Add one to see how it bumps everything else around.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink2)
                } else {
                    ForEach(events) { event in
                        let travel = event.travel > 0 ? " · \(TimeText.duration(event.travel)) travel each way" : ""
                        PlainListRow(title: event.title,
                                     detail: "\(f.range(plan.day, Double(event.start), Double(event.end))) · stay at least \(TimeText.duration(event.minStay))\(travel)") {
                            Button("Edit") { model.sheet = .editEvent(event.id) }
                                .buttonStyle(.dtn(size: .small))
                        }
                    }
                }
            }
            if !skipped.isEmpty {
                ListSection(title: "Set aside for \(which)") {
                    ForEach(skipped) { task in
                        PlainListRow(title: task.title, detail: nil) {
                            Button("Put back") { model.unskip(task.id) }
                                .buttonStyle(.dtn(size: .small))
                        }
                    }
                }
            }
            if offset > 0 {
                Text("Plans for later days assume nothing gets done before then.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.top, 6)
    }
}

struct StatCard: View {
    enum Tone { case good, warn, bad }

    let tone: Tone
    let title: String
    let detail: String

    var body: some View {
        let color: Color = tone == .good ? Theme.good : tone == .warn ? Theme.warn : Theme.bad
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                Text(detail).font(.caption).foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
        .accessibilityElement(children: .combine)
    }
}

private struct LegendItem<Swatch: View>: View {
    let text: String
    @ViewBuilder var swatch: Swatch

    var body: some View {
        HStack(spacing: 6) {
            swatch.frame(width: 14, height: 14)
            Text(text).font(.caption).foregroundStyle(Theme.ink2)
        }
    }
}

private struct ListSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

private struct PlainListRow<Trailing: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(Theme.ink3)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
    }
}
