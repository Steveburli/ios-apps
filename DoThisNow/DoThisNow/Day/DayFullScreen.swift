import SwiftUI
import DoThisNowKit

/// The Day timeline on its own, over the whole screen. The close button or a
/// swipe down on the top bar goes back to the Day tab.
struct DayFullScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        let day = model.dayShown
        let plan = engine.planDay(day)
        let offset = model.today.days(until: day, calendar: model.calendar)

        VStack(spacing: 0) {
            bar(plan: plan, offset: offset)
            ScrollViewReader { proxy in
                ScrollView {
                    DayTimeline(plan: plan, engine: engine)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
                .onAppear {
                    model.scrollDayToNow = true
                    scrollToNow(proxy)
                }
                .onChange(of: model.scrollDayToNow) { scrollToNow(proxy) }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func scrollToNow(_ proxy: ScrollViewProxy) {
        guard model.scrollDayToNow else { return }
        model.scrollDayToNow = false
        DispatchQueue.main.async {
            proxy.scrollTo(DayTimeline.nowID, anchor: UnitPoint(x: 0.5, y: 0.35))
        }
    }

    private func bar(plan: DayPlan, offset: Int) -> some View {
        let f = model.formats
        let name = offset == 0 ? "Today" : offset == 1 ? "Tomorrow" : f.weekdayName(plan.day)
        let bedtime = plan.push > 0 ? "Bedtime pushed to \(f.time(plan.day, plan.sleepStart))" : "In bed by \(f.time(plan.day, plan.bed))"
        return VStack(spacing: 2) {
            Capsule()
                .fill(Theme.line)
                .frame(width: 36, height: 5)
                .padding(.top, 4)
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                Button { close() } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40)
                }
                .accessibilityLabel("Close full screen")
                Button { model.showDay(offset: -1) } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 40)
                }
                .disabled(offset <= 0)
                .accessibilityLabel("Previous day")
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.ink)
                    Text("\(f.shortDate(plan.day)) · \(bedtime)")
                        .font(.caption)
                        .foregroundStyle(plan.push > 0 ? Theme.bad : Theme.ink3)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Button { model.showDay(offset: 1) } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 40)
                }
                .disabled(offset >= 13)
                .accessibilityLabel("Next day")
                Spacer(minLength: 4)
                Button("+ Event") { model.sheet = .newEvent(plan.day) }
                    .buttonStyle(.dtn(size: .small))
            }
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height > 70 { close() }
        })
    }

    private func close() {
        withAnimation(.snappy(duration: 0.3)) { model.setDayFullScreen(false) }
    }
}
