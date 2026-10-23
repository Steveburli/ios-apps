import SwiftUI
import DoThisNowKit

/// The vertical timeline: 1.3 points per minute, hour lines on the left, and
/// a block for everything on the day. Inbox tasks drop onto it, and your own
/// blocks move with a long press and drag.
struct DayTimeline: View {
    @Environment(AppModel.self) private var model
    let plan: DayPlan
    let engine: Engine
    @State private var dropTargeted = false

    static let px: CGFloat = 1.3
    static let nowID = "timeline-now"
    private let gutter: CGFloat = 62

    /// Today starts an hour before now; the morning that's gone isn't worth the scroll.
    private var range: (start: Double, end: Double) {
        let p = plan
        let start: Double
        let blockStarts = p.blocks.filter { !p.isToday || Double($0.end) > p.now - 60 }.map { Double($0.start) }
        if p.isToday {
            let early = min(p.wake, blockStarts.min() ?? p.wake)
            start = max((early / 60).rounded(.down) * 60, ((p.now - 60) / 60).rounded(.down) * 60)
        } else {
            let earliest = ([p.wake] + p.rocks.map(\.start) + p.events.map(\.coreStart) + blockStarts).min() ?? p.wake
            start = max(0, (earliest / 60).rounded(.down) * 60)
        }
        let latest = ([p.sleepStart + 75, start + 240] + p.events.map { $0.winEnd + $0.travel } + p.rocks.map(\.end)
                      + p.blocks.map { Double($0.end) }).max() ?? start + 240
        return (start, (latest / 60).rounded(.up) * 60)
    }

    var body: some View {
        let r = range
        let height = CGFloat(r.end - r.start) * Self.px
        GeometryReader { geo in
            canvas(width: geo.size.width, r0: r.start, r1: r.end)
        }
        .frame(height: height)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(dropTargeted ? Theme.block : Theme.line, lineWidth: dropTargeted ? 3 : 1))
        .dropDestination(for: String.self) { keys, location in
            guard let key = keys.first ?? model.draggingKey else { return false }
            let minute = max(0, Reflow.snap(r.start + Double(location.y / Self.px) - 10))
            model.schedule(key, at: minute, on: plan.day)
            return true
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
    }

    private func y(_ minute: Double, _ r0: Double) -> CGFloat {
        CGFloat(minute - r0) * Self.px
    }

    /// Top and height for a block, or nil when it ends before the timeline starts.
    private func slot(_ start: Double, _ end: Double, _ r0: Double) -> (top: CGFloat, height: CGFloat)? {
        guard end > r0 else { return nil }
        let from = max(start, r0)
        return (y(from, r0), max(12, CGFloat(end - from) * Self.px - 2))
    }

    @ViewBuilder
    private func canvas(width: CGFloat, r0: Double, r1: Double) -> some View {
        let f = model.formats
        let day = plan.day
        let blockWidth = max(40, width - gutter - 10)

        ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: r0, to: r1, by: 60)), id: \.self) { minute in
                Rectangle()
                    .fill(Theme.line)
                    .frame(width: width, height: 1)
                    .offset(y: y(minute, r0))
                Text(f.hour(day, minute))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.ink3)
                    .offset(x: 8, y: y(minute, r0) + 3)
                    .accessibilityHidden(true)
            }

            ForEach(Array(plan.rocks.enumerated()), id: \.offset) { _, rock in
                if let s = slot(rock.start, rock.end, r0) {
                    BlockLabel(title: "Work", detail: "\(f.range(day, rock.start, rock.end)) · can’t move")
                        .foregroundStyle(Theme.rockInk)
                        .background { RoundedRectangle(cornerRadius: 4).fill(Theme.rock).overlay(DotPattern()) }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .placed(width: blockWidth, slot: s, x: gutter)
                        .zIndex(2)
                }
            }

            ForEach(Array(plan.doing.enumerated()), id: \.offset) { _, doing in
                if let s = slot(doing.start, doing.end, r0) {
                    BlockLabel(title: doing.title, detail: "Doing it now")
                        .foregroundStyle(Theme.accentInk)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .placed(width: blockWidth, slot: s, x: gutter)
                        .zIndex(3)
                }
            }

            ForEach(plan.live) { event in
                eventBlocks(event, r0: r0, width: blockWidth)
            }

            ForEach(Array(plan.items.enumerated()), id: \.offset) { _, item in
                if let s = slot(item.start, item.end, r0) {
                    itemBlock(item)
                        .placed(width: blockWidth, slot: s, x: gutter)
                        .zIndex(3)
                }
            }

            ForEach(plan.blocks) { block in
                if let s = slot(Double(block.start), Double(block.end), r0) {
                    blockView(block)
                        .placed(width: blockWidth, slot: s, x: gutter)
                        .zIndex(model.draggingBlockID == block.id ? 9 : 4)
                        .animation(.snappy(duration: 0.18), value: block.start)
                }
            }

            if let meal = plan.meal, let s = slot(meal.start, meal.end, r0) {
                Button { model.sheet = .meal } label: {
                    BlockLabel(title: "Dinner: \(plan.mealMode.label.lowercased())",
                               detail: "\(f.range(day, meal.start, meal.end)) · tap for faster options")
                        .foregroundStyle(Theme.mealInk)
                        .background(Theme.meal, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .placed(width: blockWidth, slot: s, x: gutter)
                .zIndex(3)
            }

            sleepBlock(r0: r0, r1: r1, width: blockWidth)

            if plan.push > 0 {
                Text(engine.complaint(push: plan.push, day: day, at: plan.sleepStart))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.sleep, lineWidth: 2))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .frame(maxWidth: min(300, width * 0.72), alignment: .trailing)
                    .frame(width: width - 14, alignment: .trailing)
                    .offset(y: max(4, y(plan.sleepStart, r0) - 52))
                    .allowsHitTesting(false)
                    .zIndex(8)
            }

            ForEach(plan.ghostEvents) { event in
                if let s = slot(event.arrive, event.arrive + event.stay, r0) {
                    Button { model.sheet = .editEvent(event.id) } label: {
                        BlockLabel(title: event.title, detail: "Can’t make it · \(event.ghost?.text ?? "")")
                            .foregroundStyle(Theme.ink2)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.ink3, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                            .opacity(0.82)
                    }
                    .buttonStyle(.plain)
                    .placed(width: width * 0.48, slot: s, x: width - 10 - width * 0.48)
                    .zIndex(5)
                }
            }

            if plan.isToday && plan.now >= r0 && plan.now <= r1 {
                Theme.bg.opacity(0.55)
                    .frame(width: width, height: y(plan.now, r0))
                    .allowsHitTesting(false)
                    .zIndex(6)
                HStack(spacing: 0) {
                    Text("Now")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Theme.accentInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.leading, 2)
                    Rectangle().fill(Theme.accent).frame(height: 2)
                }
                .frame(width: width)
                .offset(y: y(plan.now, r0) - 8)
                .allowsHitTesting(false)
                .id(Self.nowID)
                .zIndex(7)
            }
        }
        .frame(width: width, height: CGFloat(r1 - r0) * Self.px, alignment: .topLeading)
    }

    @ViewBuilder
    private func eventBlocks(_ event: PlannedEvent, r0: Double, width: CGFloat) -> some View {
        let f = model.formats
        let day = plan.day
        let fade = event.past ? 0.45 : 1

        if let s = slot(event.winStart, event.winEnd, r0) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.jellyLine, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: width, height: s.height)
                .offset(x: gutter, y: s.top)
                .opacity(fade)
                .allowsHitTesting(false)
                .zIndex(1)
        }
        if event.travel > 0, let s = slot(event.arrive - event.travel, event.arrive, r0) {
            TravelBlock(text: "\(TimeText.duration(event.travel)) travel")
                .placed(width: width, slot: s, x: gutter)
                .opacity(fade)
                .zIndex(2)
        }
        if let s = slot(event.arrive, event.arrive + event.stay, r0) {
            BlockLabel(title: event.title, detail: "Arrive \(f.time(day, event.arrive)) · stay at least \(TimeText.duration(event.stay))",
                       trailingPadding: 36)
                .foregroundStyle(Theme.coreInk)
                .background(Theme.core, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .trailing) {
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in Capsule().frame(width: 16, height: 2) }
                    }
                    .foregroundStyle(Theme.coreInk.opacity(0.7))
                    .padding(.trailing, 12)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { value in
                            model.dragArrival(of: event, by: value.translation.height, pointsPerMinute: Self.px)
                        }
                        .onEnded { _ in model.endArrivalDrag() }
                )
                .onTapGesture { model.sheet = .editEvent(event.id) }
                .sensoryFeedback(.selection, trigger: event.arrive)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Arrival time for \(event.title)")
                .accessibilityValue("Arrive \(f.time(day, event.arrive))")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: model.nudgeArrival(of: event, by: 5)
                    case .decrement: model.nudgeArrival(of: event, by: -5)
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: "Edit event") { model.sheet = .editEvent(event.id) }
                .placed(width: width, slot: s, x: gutter)
                .opacity(fade)
                .zIndex(4)
        }
        if event.leave > event.arrive + event.stay, let s = slot(event.arrive + event.stay, event.leave, r0) {
            BlockLabel(title: nil, detail: event.squeezed ? "Leave at \(f.time(day, event.leave)) · squeezed"
                                                          : "Stay till \(f.time(day, event.leave)) if you like")
                .foregroundStyle(Theme.ink2)
                .background(Theme.jelly, in: UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 24))
                .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 24).stroke(Theme.jellyLine, lineWidth: 1.5))
                .placed(width: width, slot: s, x: gutter)
                .opacity(fade)
                .zIndex(2)
        }
        if event.travel > 0, let s = slot(event.leave, event.leave + event.travel, r0) {
            TravelBlock(text: "\(TimeText.duration(event.travel)) back")
                .placed(width: width, slot: s, x: gutter)
                .opacity(fade)
                .zIndex(2)
        }
    }

    /// A block you placed yourself. Tap for options; touch and hold, then
    /// drag, to move it.
    private func blockView(_ block: TimeBlock) -> some View {
        let f = model.formats
        let day = plan.day
        let dragging = model.draggingBlockID == block.id
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        var detail = [f.range(day, Double(block.start), Double(block.end))]
        if block.done { detail.append("done") } else if block.ref.source != .app { detail.append(block.ref.source.label) }

        return BlockLabel(title: block.title, detail: detail.joined(separator: " · "), trailingPadding: 34)
            .foregroundStyle(Theme.blockInk)
            .strikethrough(block.done)
            .background(Theme.block.opacity(block.done ? 0.45 : 1), in: shape)
            .overlay(alignment: .trailing) {
                Group {
                    if block.done {
                        Image(systemName: "checkmark").font(.caption.weight(.bold))
                    } else {
                        VStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { _ in Capsule().frame(width: 14, height: 2) }
                        }
                    }
                }
                .foregroundStyle(Theme.blockInk.opacity(0.75))
                .padding(.trailing, 11)
            }
            .overlay { if dragging { shape.strokeBorder(Theme.ink, lineWidth: 2) } }
            .scaleEffect(dragging ? 1.02 : 1)
            .shadow(color: .black.opacity(dragging ? 0.25 : 0), radius: 10, y: 6)
            .contentShape(shape)
            .onTapGesture { model.sheet = .block(block.id) }
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        if case .second(true, let drag?) = value {
                            model.dragBlock(block.id, by: drag.translation.height, pointsPerMinute: Self.px)
                        }
                    }
                    .onEnded { _ in model.endBlockDrag() }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: dragging) { _, now in now }
            .sensoryFeedback(.selection, trigger: block.start)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(block.title)
            .accessibilityValue("\(f.range(day, Double(block.start), Double(block.end)))\(block.done ? ", done" : "")")
            .accessibilityHint("Swipe up or down to move it five minutes. Others move out of its way.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.nudgeBlock(block.id, by: 5)
                case .decrement: model.nudgeBlock(block.id, by: -5)
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Options") { model.sheet = .block(block.id) }
    }

    private func itemBlock(_ item: PlanItem) -> some View {
        let f = model.formats
        let chunk = item.chunk
        var note = [f.range(plan.day, item.start, item.end)]
        if item.parts > 1 { note.append("part \(item.part) of \(item.parts)") }
        if item.squished { note.append("squeezed") }
        if item.filler { note.append("if you have room") } else if chunk.must { note.append("must do") }
        let radius: CGFloat = item.squished ? 5 : 14
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return Button { model.sheet = .dayItem(chunk.id) } label: {
            BlockLabel(title: chunk.title, detail: note.joined(separator: " · "))
                .foregroundStyle(Theme.softInk)
                .background {
                    if item.filler {
                        shape.fill(Theme.surface).overlay(Stripes(color: Theme.soft, spacing: 13, lineWidth: 7).clipShape(shape))
                    } else {
                        shape.fill(Theme.soft)
                    }
                }
                .overlay {
                    if item.squished {
                        shape.strokeBorder(Theme.bad, lineWidth: 2)
                    } else if item.filler {
                        shape.strokeBorder(Theme.softLine, lineWidth: 1.5)
                    } else {
                        shape.strokeBorder(Theme.softLine.opacity(0.6), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sleepBlock(r0: Double, r1: Double, width: CGFloat) -> some View {
        let f = model.formats
        let top = y(plan.sleepStart, r0)
        let height = max(12, CGFloat(r1 - plan.sleepStart) * Self.px)
        BlockLabel(title: "Sleep", detail: f.time(plan.day, plan.sleepStart) + (plan.push > 0 ? " · \(TimeText.duration(plan.push)) late" : ""))
            .padding(.top, 5)
            .foregroundStyle(Theme.sleepInk)
            .background(Theme.sleep, in: UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
            .frame(width: width, height: height, alignment: .topLeading)
            .phaseAnimator([0.0, -4.0, 4.0, -4.0, 4.0, 0.0], trigger: plan.push) { view, shake in
                view.offset(x: plan.push > 0 ? shake : 0)
            } animation: { _ in
                .easeInOut(duration: 0.07)
            }
            .offset(x: gutter, y: top)
            .zIndex(3)
    }
}

/// Title and detail inside a block, clipped to its height.
private struct BlockLabel: View {
    let title: String?
    let detail: String?
    var trailingPadding: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .opacity(0.85)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, trailingPadding)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

private struct TravelBlock: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.jellyLine).frame(width: 3)
            Text(text)
                .font(.caption2)
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Stripes(color: Theme.jelly, spacing: 12, lineWidth: 6))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Diagonal stripes, for travel and filler blocks.
struct Stripes: View {
    let color: Color
    var spacing: CGFloat = 12
    var lineWidth: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}

/// The speckle on work blocks, so a rock looks like stone.
private struct DotPattern: View {
    var body: some View {
        Canvas { context, size in
            for row in stride(from: 0, to: size.height, by: 10) {
                for column in stride(from: 0, to: size.width, by: 10) {
                    context.fill(Path(ellipseIn: CGRect(x: column, y: row, width: 2, height: 2)), with: .color(.white.opacity(0.16)))
                    context.fill(Path(ellipseIn: CGRect(x: column + 5, y: row + 7, width: 2, height: 2)), with: .color(.black.opacity(0.16)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    /// Sizes a block and moves it to its place on the timeline.
    func placed(width: CGFloat, slot: (top: CGFloat, height: CGFloat), x: CGFloat) -> some View {
        frame(width: width, height: slot.height, alignment: .topLeading)
            .offset(x: x, y: slot.top)
    }
}
