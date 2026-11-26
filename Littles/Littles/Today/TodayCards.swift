import SwiftUI
import LittlesKit

/// "Leave in 18 minutes" on school mornings, with what to pack.
struct CountdownCard: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    let now: Date

    var body: some View {
        let today = Dates.key(now)
        let minute = Dates.minutes(now)
        if model.state.settings.countdown,
           let leave = Agenda.leave(on: today, state: model.state, travelMinutes: model.state.settings.travelMinutes),
           leave.kidIDs.contains(kid.id), minute >= leave.minute - 120, minute <= leave.minute + 20 {
            let pack = Agenda.packList(on: today, state: model.state)
            let left = leave.minute - minute
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(left > 0 ? "🚗 Leave in \(Dates.duration(Double(left) * 60))" : "🚗 Time to go!")
                        .font(Theme.display(20))
                        .foregroundStyle(left <= 5 ? Theme.warn : Theme.ink)
                    Spacer()
                    Text("at \(Dates.clock(leave.minute))").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                Text("\(leave.entry.title)" + (leave.entry.place.isEmpty ? "" : " · \(leave.entry.place)"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                ForEach(pack) { line in
                    Button {
                        model.togglePacked(day: today, id: line.id)
                    } label: {
                        Label(line.title, systemImage: line.packed ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(line.packed ? Theme.muted : Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }
}

/// "Ibuprofen OK again at 2:40 PM".
struct MedicineCard: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    let now: Date

    var body: some View {
        let statuses = MedicineTimer.status(model.state.logs, kidID: kid.id, now: now)
        if !statuses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("💊 Medicine").font(.headline)
                ForEach(statuses, id: \.rule.id) { status in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.rule.name).font(.subheadline.weight(.semibold))
                            Text("Last at \(status.last.formatted(date: .omitted, time: .shortened)) · \(status.dosesToday) in 24 hours")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if status.nextOK <= now {
                            Pill(text: "OK now if needed", color: Theme.good)
                        } else {
                            Pill(text: (status.atLimit ? "Daily limit · " : "Next ") + status.nextOK.formatted(date: .omitted, time: .shortened),
                                 color: status.atLimit ? Theme.warn : Theme.accent)
                        }
                    }
                }
            }
            .card()
        }
    }
}

/// When to call the doctor, while a kid is sick.
struct SickCard: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    let now: Date

    var body: some View {
        let recent = model.state.logs.filter {
            $0.kidID == kid.id && ($0.kind == .symptom || $0.kind == .temperature) && now.timeIntervalSince($0.start) < 48 * 3600
        }
        let sick = recent.contains { !$0.symptoms.isEmpty || ($0.temperatureF ?? 0) >= 100.4 }
        if sick {
            let latestTemp = recent.filter { $0.temperatureF != nil }.max { $0.start < $1.start }?.temperatureF
            let symptoms = Array(Set(recent.flatMap { $0.symptoms })).sorted()
            let hours = SickAdvice.feverHours(model.state.logs, kidID: kid.id, now: now)
            let reasons = SickAdvice.callReasons(ageMonths: kid.ageMonths(on: now), temperatureF: latestTemp, symptoms: symptoms, feverHours: hours)
            VStack(alignment: .leading, spacing: 8) {
                Text("🤒 \(kid.name) isn't feeling well").font(.headline)
                Text(([latestTemp.map { model.units.temperature($0) }].compactMap { $0 } + symptoms).joined(separator: " · ")
                     + (hours > 0 ? " · fever for \(Dates.duration(hours * 3600))" : ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                ForEach(reasons, id: \.self) { reason in
                    Label(reason, systemImage: "phone.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.warn)
                }
                Text(SickAdvice.emergency).font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }
}

/// "Next nap window 2:30–3:30 PM", from the awake window for the age.
struct NapCard: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    let now: Date

    var body: some View {
        let age = kid.ageMonths(on: now)
        if age < 48, let window = SleepGuide.nextSleep(model.state.logs, kidID: kid.id, ageMonths: age, now: now),
           window.to > now.addingTimeInterval(-1800) {
            let guide = SleepGuide.window(ageMonths: age)
            HStack(spacing: 12) {
                Text("🌙").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.from <= now ? "Sleepy window now" : "Next sleep window")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(window.from <= now ? Theme.warn : Theme.accent)
                    Text("\(window.from.formatted(date: .omitted, time: .shortened))–\(window.to.formatted(date: .omitted, time: .shortened))")
                        .font(.headline)
                    Text("Awake windows at \(Age.short(months: age)): about \(Dates.duration(Double(guide.minMinutes) * 60))–\(Dates.duration(Double(guide.maxMinutes) * 60)) · \(guide.naps) naps")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .card()
        }
    }
}

/// Potty training: today's tally, the dry streak and one-tap buttons.
struct PottyCard: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid

    var body: some View {
        if model.state.settings.potty[kid.id]?.on == true {
            let today = Dates.key(Date())
            let tally = PottyStats.day(model.state.logs, kidID: kid.id, day: today)
            let streak = PottyStats.dryStreak(model.state.logs, kidID: kid.id, today: today)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("🚽 Potty training").font(.headline)
                    Spacer()
                    if streak > 0 { Pill(text: "\(streak)-day dry streak 🔥", color: Theme.good) }
                }
                HStack(spacing: 4) {
                    ForEach(0..<max(tally.successes, 1), id: \.self) { index in
                        Text(index < tally.successes ? "⭐️" : "☆").font(.title2).foregroundStyle(Theme.line)
                    }
                    Spacer()
                    Text("\(tally.tries) tries · \(tally.accidents) accidents").font(.caption).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 8) {
                    ForEach([PottyKind.pee, .poop, .tried, .accident]) { kind in
                        Button(kind.title) {
                            model.save(LogEntry(kidID: kid.id, kind: .potty, start: Date(), potty: kind))
                        }
                        .buttonStyle(.bordered)
                        .tint(kind == .accident ? Theme.warn : Theme.accent)
                    }
                }
            }
            .card()
        }
    }
}

/// The picture charts (bedtime, morning) for this kid, with today's progress.
struct ChartsRow: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    @State private var open: RoutineChart?

    var body: some View {
        let charts = model.state.charts.filter { $0.kidIDs.isEmpty || $0.kidIDs.contains(kid.id) }
        let today = Dates.key(Date())
        if kid.ageMonths(on: Date()) >= 18 && !charts.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(charts) { chart in
                        let done = chart.done(day: today, kidID: kid.id, keys: model.state.chartDone)
                        Button { open = chart } label: {
                            HStack(spacing: 8) {
                                Text(chart.emoji).font(.title2)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(chart.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                                    Text(done == chart.steps.count ? "All done! 🎉" : "\(done) of \(chart.steps.count)")
                                        .font(.caption)
                                        .foregroundStyle(done == chart.steps.count ? Theme.good : Theme.muted)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(item: $open) { chart in
                ChartSheet(chartID: chart.id, kid: kid).environmentObject(model)
            }
        }
    }
}

/// A big, tappable picture checklist a preschooler can follow.
struct ChartSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let chartID: String
    let kid: Kid

    var body: some View {
        let today = Dates.key(Date())
        let chart = model.state.charts.first { $0.id == chartID }
        NavigationStack {
            ScrollView {
                if let chart {
                    let done = chart.done(day: today, kidID: kid.id, keys: model.state.chartDone)
                    let streak = chart.streak(today: today, kidID: kid.id, keys: model.state.chartDone)
                    VStack(spacing: 12) {
                        ForEach(Array(chart.steps.enumerated()), id: \.offset) { index, step in
                            let on = model.state.chartDone.contains(RoutineChart.key(day: today, chartID: chart.id, kidID: kid.id, step: index))
                            Button {
                                model.toggleChartStep(chartID: chart.id, kidID: kid.id, step: index)
                            } label: {
                                HStack(spacing: 16) {
                                    Text(step.emoji).font(.system(size: 44))
                                    Text(step.title).font(Theme.display(24)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Image(systemName: on ? "star.fill" : "star")
                                        .font(.system(size: 30))
                                        .foregroundStyle(on ? Color.yellow : Theme.line)
                                }
                                .padding(16)
                                .background(on ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        if done == chart.steps.count {
                            Text("🎉 All done, \(kid.name)!").font(Theme.display(28)).padding(.top, 8)
                        }
                        if streak > 1 {
                            Text("\(streak) days in a row").font(.headline).foregroundStyle(Theme.good)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(chart.map { "\($0.emoji) \($0.title)" } ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
