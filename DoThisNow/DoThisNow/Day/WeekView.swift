import SwiftUI
import UIKit
import DoThisNowKit

/// The whole week, Monday to Sunday, on one screen: a thin column per day
/// with colored bars and small symbols for the time that's spoken for (work,
/// events, dinner, sleep, the alarm) and a dot for each task you placed. It's
/// look-only: tap a day to open it on the Day, swipe sideways for another week.
struct WeekView: View {
    @Environment(AppModel.self) private var model
    /// Set in full screen, where the week has its own close button.
    var onClose: (() -> Void)? = nil

    private let gutter: CGFloat = 30
    private let labelHeight: CGFloat = 40

    var body: some View {
        let days = model.week(of: model.dayShown)
        let engine = model.engine
        let columns = days.map { column(for: $0, engine: engine) }
        let range = Self.range(of: columns)

        VStack(alignment: .leading, spacing: 10) {
            header(days)
            GeometryReader { geo in
                grid(columns, range: range, size: geo.size)
            }
            .frame(minHeight: 260)
            legend
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(SwipeRecognizer(direction: .left) { step(1) })
        .gesture(SwipeRecognizer(direction: .right) { step(-1) })
    }

    private func step(_ weeks: Int) {
        withAnimation(.snappy(duration: 0.25)) { model.showWeek(offset: weeks) }
    }

    // MARK: Header

    private func header(_ days: [CalendarDay]) -> some View {
        let f = model.formats
        let first = days.first ?? model.dayShown
        let last = days.last ?? model.dayShown
        return HStack(spacing: 4) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Close full screen")
            }
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 40)
            }
            .disabled(!model.canShowWeek(offset: -1))
            .accessibilityLabel("Previous week")
            VStack(alignment: .leading, spacing: 0) {
                Text(days.contains(model.today) ? "This week" : "Week")
                    .font(Theme.display(onClose == nil ? 30 : 22))
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    Text("\(f.shortDate(first)) – \(f.shortDate(last))")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if !days.contains(model.today) {
                        TodayPill { withAnimation(.snappy(duration: 0.25)) { model.goToToday() } }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Button { step(1) } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 40)
            }
            .disabled(!model.canShowWeek(offset: 1))
            .accessibilityLabel("Next week")
            Spacer(minLength: 4)
            Button {
                withAnimation(.snappy(duration: 0.3)) { model.setWeekShown(false) }
            } label: {
                Label("Day", systemImage: "calendar.day.timeline.left")
            }
            .buttonStyle(.dtn(size: .small))
            .accessibilityLabel("Back to the day")
        }
        .foregroundStyle(Theme.ink2)
    }

    // MARK: Grid

    private func grid(_ columns: [DayColumn], range: (start: Double, end: Double), size: CGSize) -> some View {
        let plotHeight = max(120, size.height - labelHeight)
        let px = plotHeight / CGFloat(max(60, range.end - range.start))
        let columnWidth = max(24, (size.width - gutter) / 7)
        let hours = Array(stride(from: (range.start / 180).rounded(.up) * 180, to: range.end, by: 180))

        return ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { minute in
                let y = labelHeight + CGFloat(minute - range.start) * px
                Rectangle()
                    .fill(Theme.line)
                    .frame(width: size.width - gutter, height: 1)
                    .offset(x: gutter, y: y)
                Text(model.formats.hour(model.today, minute))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(Theme.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: gutter - 3, alignment: .leading)
                    .offset(y: y - 6)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(columns, id: \.day) { column in
                    dayColumn(column, range: range, px: px, width: columnWidth, plotHeight: plotHeight)
                }
            }
            .offset(x: gutter)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func dayColumn(_ column: DayColumn, range: (start: Double, end: Double), px: CGFloat,
                           width: CGFloat, plotHeight: CGFloat) -> some View {
        let day = column.day
        let isToday = day == model.today
        let open = model.canShow(day)
        let selected = day == model.dayShown && !isToday
        let inner = max(10, width - 6)
        let y: (Double) -> CGFloat = { CGFloat(max(range.start, min(range.end, $0)) - range.start) * px }

        return Button { withAnimation(.snappy(duration: 0.3)) { model.openDayFromWeek(day) } } label: {
            VStack(spacing: 0) {
                dayLabel(day, isToday: isToday)
                    .frame(height: labelHeight)
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.surface.opacity(0.7))
                    ForEach(Array(column.bars.enumerated()), id: \.offset) { _, bar in
                        let top = y(bar.start)
                        let height = y(bar.end) - top
                        if height > 0.5 {
                            barView(bar, width: inner, height: max(2, height), pushed: column.pushed)
                                .offset(y: top)
                        }
                    }
                    ForEach(Array(column.dots.enumerated()), id: \.offset) { _, dot in
                        Circle()
                            .fill(Theme.block.opacity(dot.done ? 0.4 : 1))
                            .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 1))
                            .frame(width: 8, height: 8)
                            .offset(x: dot.shift, y: y(dot.minute) - 4)
                    }
                    if let alarm = column.alarm, alarm >= range.start, alarm <= range.end {
                        HStack(spacing: 0) {
                            Image(systemName: "alarm.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.accent)
                            Rectangle().fill(Theme.accent).frame(height: 1.5)
                        }
                        .frame(width: inner)
                        .offset(y: y(alarm) - 5)
                    }
                    if isToday, let now = column.now, now >= range.start, now <= range.end {
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: inner + 4, height: 2)
                            .offset(y: y(now) - 1)
                    }
                }
                .frame(width: inner, height: plotHeight, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.ink3, lineWidth: 1.5)
                    }
                }
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .opacity(open ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(column))
        .accessibilityHint(Text(open ? "Opens this day" : ""))
        .accessibilityAddTraits(open ? .isButton : [])
    }

    private func dayLabel(_ day: CalendarDay, isToday: Bool) -> some View {
        let calendar = model.calendar
        let symbols = calendar.veryShortWeekdaySymbols
        let index = day.weekdayIndex(calendar: calendar)
        return VStack(spacing: 2) {
            Text(symbols.indices.contains(index) ? symbols[index] : "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Theme.accent : Theme.ink3)
            Text("\(day.day)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(isToday ? Theme.accentInk : Theme.ink)
                .frame(width: 24, height: 24)
                .background { if isToday { Circle().fill(Theme.accent) } }
        }
    }

    private func barView(_ bar: Bar, width: CGFloat, height: CGFloat, pushed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(4, height / 2), style: .continuous)
        return shape
            .fill(bar.kind.color)
            .overlay {
                if bar.kind == .sleep && pushed && bar.isEvening {
                    shape.strokeBorder(Theme.bad, lineWidth: 2)
                }
            }
            .overlay {
                if height >= 14 {
                    Image(systemName: bar.kind.symbol)
                        .font(.system(size: min(11, height - 4), weight: .semibold))
                        .foregroundStyle(bar.kind.ink)
                }
            }
            .frame(width: width, height: height)
    }

    private var legend: some View {
        FlowLayout(spacing: 10) {
            ForEach(BarKind.allCases, id: \.self) { kind in
                LegendChip(text: kind.label) {
                    RoundedRectangle(cornerRadius: 3).fill(kind.color)
                        .overlay(Image(systemName: kind.symbol).font(.system(size: 8, weight: .semibold)).foregroundStyle(kind.ink))
                }
            }
            LegendChip(text: "Alarm") {
                Image(systemName: "alarm.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent)
            }
            LegendChip(text: "Task you placed") {
                Circle().fill(Theme.block).padding(3)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Data

    enum BarKind: CaseIterable {
        case work, event, meal, sleep

        var color: Color {
            switch self {
            case .work: Theme.rock
            case .event: Theme.core
            case .meal: Theme.meal
            case .sleep: Theme.sleep
            }
        }

        var ink: Color {
            switch self {
            case .work: Theme.rockInk
            case .event: Theme.coreInk
            case .meal: Theme.mealInk
            case .sleep: Theme.sleepInk
            }
        }

        var symbol: String {
            switch self {
            case .work: "briefcase.fill"
            case .event: "star.fill"
            case .meal: "fork.knife"
            case .sleep: "moon.fill"
            }
        }

        var label: String {
            switch self {
            case .work: "Work"
            case .event: "Event"
            case .meal: "Dinner"
            case .sleep: "Sleep"
            }
        }
    }

    struct Bar {
        let kind: BarKind
        let start: Double
        let end: Double
        var isEvening = false
    }

    struct Dot {
        let minute: Double
        let done: Bool
        /// Sideways nudge, so tasks that start close together don't cover each other.
        var shift: CGFloat = 0
    }

    struct DayColumn {
        let day: CalendarDay
        let wake: Double
        let bars: [Bar]
        let dots: [Dot]
        let alarm: Double?
        let now: Double?
        let pushed: Bool
        let eventCount: Int
        let workHours: Double
    }

    private func column(for day: CalendarDay, engine: Engine) -> DayColumn {
        let plan = engine.planDay(day)
        var bars: [Bar] = []
        bars.append(Bar(kind: .sleep, start: 0, end: plan.wake))
        bars += plan.rocks.map { Bar(kind: .work, start: $0.start, end: $0.end) }
        if let meal = plan.meal { bars.append(Bar(kind: .meal, start: meal.start, end: meal.end)) }
        bars += plan.live.map { event in
            Bar(kind: .event, start: event.coreStart, end: max(event.arrive + event.stay, event.leave) + event.travel)
        }
        bars.append(Bar(kind: .sleep, start: plan.sleepStart, end: 30 * 60, isEvening: true))

        var dots: [Dot] = []
        var lastMinute = -Double.infinity
        var nudge = 0
        for block in plan.blocks.sorted(by: { $0.start < $1.start }) {
            let minute = Double(block.start + block.end) / 2
            nudge = minute - lastMinute < 25 ? nudge + 1 : 0
            lastMinute = minute
            let shift = nudge == 0 ? 0 : CGFloat(nudge % 2 == 1 ? 7 : -7) * CGFloat((nudge + 1) / 2)
            dots.append(Dot(minute: minute, done: block.done, shift: max(-14, min(14, shift))))
        }

        let alarm = engine.alarmTime(on: day).map { model.calendar.minuteOfDay($0) }
        return DayColumn(day: day, wake: plan.wake, bars: bars, dots: dots, alarm: alarm,
                         now: plan.isToday ? plan.now : nil, pushed: plan.push > 0,
                         eventCount: plan.live.count,
                         workHours: plan.rocks.reduce(0) { $0 + $1.end - $1.start } / 60)
    }

    /// One time range for the whole week, so the columns line up: from an
    /// hour before the earliest wake-up (or alarm) to an hour after the latest bedtime.
    static func range(of columns: [DayColumn]) -> (start: Double, end: Double) {
        let firsts = columns.map { column in
            ([column.wake, column.alarm ?? column.wake] + column.bars.filter { $0.start > 0 }.map(\.start)
             + column.dots.map(\.minute)).min() ?? column.wake
        }
        let lasts = columns.map { column in
            ([column.bars.first(where: \.isEvening)?.start ?? 22 * 60]
             + column.bars.filter { !$0.isEvening }.map(\.end) + column.dots.map(\.minute)).max() ?? 22 * 60
        }
        let start = max(0, (((firsts.min() ?? 6 * 60) - 60) / 60).rounded(.down) * 60)
        let end = min(30 * 60, (((lasts.max() ?? 22 * 60) + 60) / 60).rounded(.up) * 60)
        return (start, max(end, start + 8 * 60))
    }

    private func summary(_ column: DayColumn) -> String {
        let f = model.formats
        let day = column.day
        var parts = [day == model.today ? "Today, \(f.shortDate(day))" : f.shortDate(day)]
        if column.workHours > 0 { parts.append("work \(TimeText.duration(column.workHours * 60))") }
        if column.eventCount > 0 { parts.append("\(column.eventCount) event\(column.eventCount == 1 ? "" : "s")") }
        if !column.dots.isEmpty { parts.append("\(column.dots.count) task\(column.dots.count == 1 ? "" : "s") placed") }
        if let alarm = column.alarm { parts.append("alarm at \(f.time(day, alarm))") }
        if column.pushed { parts.append("bedtime pushed") }
        if !model.canShow(day) { parts.append(day < model.today ? "past" : "too far ahead") }
        return parts.joined(separator: ", ")
    }
}

/// The Week button at the top of the Day tab: shows the whole week, or goes back to the day.
struct WeekButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let on = model.weekShown && model.dayPage == .timeline
        Button {
            withAnimation(.snappy(duration: 0.3)) { model.setWeekShown(!on) }
        } label: {
            Text("Week")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Theme.accentInk : Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(on ? Theme.accent : Theme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Back to the day" : "Show the week")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension View {
    /// Swipe left for the next day and right for the one before. Ignored
    /// while something on the Day is being dragged.
    func daySwipes() -> some View { modifier(DaySwipes()) }
}

private struct DaySwipes: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .gesture(SwipeRecognizer(direction: .left) { go(1) })
            .gesture(SwipeRecognizer(direction: .right) { go(-1) })
    }

    private func go(_ days: Int) {
        guard !model.isDraggingOnDay else { return }
        withAnimation(.snappy(duration: 0.25)) { model.showDay(offset: days) }
    }
}

/// The small "Today" button that shows when you're looking at another day.
struct TodayPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Today")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accentInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to today")
    }
}

private struct LegendChip<Swatch: View>: View {
    let text: String
    @ViewBuilder var swatch: Swatch

    var body: some View {
        HStack(spacing: 5) {
            swatch.frame(width: 14, height: 14)
            Text(text).font(.caption2).foregroundStyle(Theme.ink2)
        }
    }
}

/// A quick sideways swipe, read by UIKit so it works inside a vertical
/// scroll view and alongside dragging blocks. A slow drag or a press and
/// hold never counts as a swipe.
struct SwipeRecognizer: UIGestureRecognizerRepresentable {
    let direction: UISwipeGestureRecognizer.Direction
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UISwipeGestureRecognizer {
        let recognizer = UISwipeGestureRecognizer()
        recognizer.direction = direction
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
