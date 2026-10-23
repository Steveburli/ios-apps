import SwiftUI
import DoThisNowKit

/// The Wake tab: when to get up so the morning fits before you have to
/// leave, when to be in bed for your sleep goal, and the alarm.
struct WakeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        let plan = engine.wakePlan(for: engine.wakeMorning())
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Wake")
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                PlanCard(plan: plan)
                DayPlanWarning(plan: plan)
                RoutineCard(plan: plan)
                AlarmCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 32)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The two times that matter, and how long until bed.
private struct PlanCard: View {
    @Environment(AppModel.self) private var model
    let plan: WakePlan

    var body: some View {
        let f = model.formats
        let isToday = plan.day == model.today
        let wakeDate = plan.day.date(atMinute: plan.wake, calendar: model.calendar)
        let bedDate = plan.day.date(atMinute: plan.inBed, calendar: model.calendar)
        let sleepGoal = model.state.wake.sleepMinutes
        VStack(alignment: .leading, spacing: 14) {
            Text(isToday ? "THIS MORNING" : model.today.adding(days: 1, calendar: model.calendar) == plan.day
                 ? "TOMORROW" : f.weekdayName(plan.day).uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1)
                .foregroundStyle(Theme.ink3)
            HStack(alignment: .top, spacing: 18) {
                bigTime("Wake up", f.time(wakeDate), symbol: "sun.max.fill")
                if !isToday {
                    bigTime("In bed by", f.time(bedDate), symbol: "moon.fill")
                }
            }
            Text(plan.reason + ".")
                .font(.subheadline)
                .foregroundStyle(Theme.ink2)
            if !isToday {
                Text(status(bed: bedDate, wake: wakeDate, goal: sleepGoal))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(bedDate < model.now ? Theme.bad : Theme.ink)
            }
            Button("Use these for my Day plan") { model.useWakePlan(plan) }
                .buttonStyle(.dtn(size: .small))
        }
        .card()
    }

    private func bigTime(_ label: String, _ time: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink2)
            Text(time)
                .font(Theme.display(34))
                .foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func status(bed: Date, wake: Date, goal: Int) -> String {
        let now = model.now
        if bed > now {
            let minutes = bed.timeIntervalSince(now) / 60
            return "Bedtime is in \(TimeText.duration(minutes)), for \(TimeText.duration(goal)) of sleep."
        }
        let sleep = max(0, wake.timeIntervalSince(now) / 60 - Double(model.state.wake.fallAsleep))
        return "Past bedtime: going to sleep now still gets you \(TimeText.duration(sleep))."
    }
}

/// When today's Day plan keeps you up past the bedtime the morning needs.
private struct DayPlanWarning: View {
    @Environment(AppModel.self) private var model
    let plan: WakePlan

    var body: some View {
        let today = model.today
        if plan.day == today.adding(days: 1, calendar: model.calendar) {
            let dayPlan = model.engine.planDay(today)
            let bedtime = plan.inBed + 1440
            if dayPlan.sleepStart > bedtime + 5 {
                let sleep = 1440 + plan.wake - dayPlan.sleepStart - Double(model.state.wake.fallAsleep)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today’s plan runs until \(model.formats.time(today, dayPlan.sleepStart)).")
                        .font(.subheadline.weight(.bold))
                    Text("That leaves \(TimeText.duration(max(0, sleep))) of sleep. Move or drop something on the Day to get to bed on time.")
                        .font(.subheadline)
                    Button("Open the Day") { model.tab = .day }
                        .buttonStyle(.dtn(size: .small))
                }
                .foregroundStyle(Theme.ink)
                .banner()
            }
        }
    }
}

/// Everything between waking and leaving, with where each time came from.
private struct RoutineCard: View {
    @Environment(AppModel.self) private var model
    let plan: WakePlan

    var body: some View {
        let f = model.formats
        let wake = model.state.wake
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your morning")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(TimeText.duration(plan.routine))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.ink2)
            }
            ForEach(plan.steps) { step in
                Button { model.sheet = .routineStep(step.id) } label: {
                    row(step.title, step.estimate)
                }
                .buttonStyle(.plain)
            }
            Button("+ Add a step") { model.sheet = .routineStep(nil) }
                .buttonStyle(.dtn(size: .small))

            Divider()
            if let commute = plan.commute {
                row(commute.title, commute.estimate)
            }
            if plan.leave != nil {
                HStack {
                    Text("Buffer").foregroundStyle(Theme.ink)
                    Spacer()
                    Text(TimeText.duration(plan.buffer)).foregroundStyle(Theme.ink2)
                }
                .font(.subheadline)
            }
            if let leave = plan.leave {
                Text("Leave by \(f.time(plan.day, leave)), so wake up at \(f.time(plan.day, plan.wake)).")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink3)
            }
            HStack(spacing: 8) {
                Button("Sleep and commute") { model.sheet = .sleep }
                    .buttonStyle(.dtn(size: .small))
                Button("Time my morning") {
                    model.linkRoutineToTrack()
                    model.tab = .track
                }
                .buttonStyle(.dtn(size: .small))
            }
            Text("Sleep goal \(TimeText.duration(wake.sleepMinutes)), \(wake.fallAsleep) min to fall asleep. Times with a stopwatch come from the Track tab, with odd mornings left out.")
                .font(.caption)
                .foregroundStyle(Theme.ink3)
        }
        .card()
    }

    private func row(_ title: String, _ estimate: Estimate) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline).foregroundStyle(Theme.ink)
                Text(estimate.detail).font(.caption).foregroundStyle(Theme.ink3)
            }
            Spacer()
            EstimateChip(estimate: estimate)
        }
        .contentShape(Rectangle())
    }
}

/// The alarm at a glance.
private struct AlarmCard: View {
    @Environment(AppModel.self) private var model
    @State private var busy = false

    var body: some View {
        let alarm = model.state.wake.alarm
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { alarm.on }, set: { on in
                busy = true
                Task {
                    await model.setAlarm(on: on)
                    busy = false
                }
            })) {
                Text("Alarm").font(.headline).foregroundStyle(Theme.ink)
            }
            .tint(Theme.accent)
            .disabled(busy)

            if alarm.on {
                if let next = model.nextAlarm {
                    Text("Next: \(model.formats.when(next.date, now: model.now))\(alarm.followPlan ? ", your suggested time" : "")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                } else {
                    Text("No alarm in the next week. Pick days in the alarm settings.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink2)
                }
                if alarm.requireScan && alarm.codes.isEmpty {
                    Text("Save a code to scan, or the alarm will stop with a swipe like any other.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.bad)
                } else if alarm.needsScan {
                    Text("Turns off only when you scan \(alarm.codes.map(\.name).joined(separator: " or ")). Until then it rings again every \(alarm.backupEvery) min.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink3)
                }
            }
            FlowLayout {
                Button("Alarm settings") { model.sheet = .alarm }
                    .buttonStyle(.dtn(size: .small))
                if alarm.on && alarm.needsScan, model.nextAlarm != nil {
                    Button("Up early? Scan to turn it off") { model.scanMode = .stopAlarm }
                        .buttonStyle(.dtn(size: .small))
                }
            }
        }
        .card()
    }
}

extension AppModel {
    /// Gives each routine step an activity on the Track tab, so timing it
    /// there sets its length.
    func linkRoutineToTrack() {
        for index in state.wake.routine.indices where state.wake.routine[index].activityID == nil {
            state.wake.routine[index].activityID = activityID(for: state.wake.routine[index].title)
        }
        if state.wake.commuteOn && state.wake.commute.activityID == nil {
            state.wake.commute.activityID = activityID(for: state.wake.commute.title)
        }
        commit()
    }
}
