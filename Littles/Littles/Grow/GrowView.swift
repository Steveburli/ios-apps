import SwiftUI
import Charts
import LittlesKit

enum GrowSection: String, CaseIterable, Identifiable {
    case milestones, growth, tips
    var id: String { rawValue }
    var title: String {
        switch self {
        case .milestones: return "Milestones"
        case .growth: return "Growth"
        case .tips: return "Tips"
        }
    }
}

/// The Grow tab: the CDC-style milestone checklist for the kid's age, their
/// growth over time, and short scripts for hard parenting moments.
struct GrowView: View {
    @EnvironmentObject var model: AppModel
    @State private var section: GrowSection = Screenshots.shows("tips") ? .tips : (Screenshots.shows("growth") ? .growth : .milestones)
    @State private var months: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    KidPicker(selection: Binding(get: { model.kidID }, set: { model.select($0); months = nil }))
                        .padding(.horizontal, -16)
                    Picker("Section", selection: $section) {
                        ForEach(GrowSection.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if let kid = model.kid {
                        switch section {
                        case .milestones: MilestonesSection(kid: kid, months: $months)
                        case .growth: GrowthSection(kid: kid)
                        case .tips: TipsSection()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Grow")
        }
    }
}

struct MilestonesSection: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    @Binding var months: Int?

    var body: some View {
        let age = kid.ageMonths(on: Date())
        let shown = months ?? Milestones.current(ageMonths: age)
        let statuses = model.state.milestones[kid.id] ?? [:]
        let progress = Milestones.progress(months: shown, statuses: statuses)
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Milestones.ages, id: \.self) { checkpoint in
                        let done = Milestones.progress(months: checkpoint, statuses: statuses)
                        Button { months = checkpoint } label: {
                            VStack(spacing: 2) {
                                Text(checkpoint < 24 ? "\(checkpoint)m" : (checkpoint % 12 == 0 ? "\(checkpoint / 12)y" : "\(checkpoint / 12)½y"))
                                    .font(.subheadline.weight(.bold))
                                Circle()
                                    .fill(done.done == done.total ? Theme.good : (checkpoint <= age ? Theme.warn : Color.clear))
                                    .frame(width: 5, height: 5)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(checkpoint == shown ? Color.white : Theme.ink)
                            .background(checkpoint == shown ? Theme.color(kid) : Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(checkpoint == shown ? Theme.color(kid) : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("By \(Milestones.ageTitle(shown))")
                    .font(Theme.display(22))
                Text("\(progress.done) of \(progress.total) checked · \(kid.name) is \(kid.ageLabel(on: Date()))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                    .tint(Theme.color(kid))
            }
            .card()
            let mention = Milestones.toMention(ageMonths: age, statuses: statuses)
            if !mention.isEmpty && shown == Milestones.current(ageMonths: age) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("🩺 Bring up at the next checkup").font(.headline)
                    ForEach(mention) { item in
                        Text("• \(item.text) (\(Milestones.ageTitle(item.months)))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            ForEach(MilestoneDomain.allCases) { domain in
                let items = Milestones.list(for: shown).filter { $0.domain == domain }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(domain.emoji) \(domain.title)").font(.headline)
                        ForEach(items) { item in
                            MilestoneRow(item: item, kidID: kid.id)
                        }
                    }
                    .card()
                }
            }
            Text("Milestones are paraphrased from the CDC's \"Learn the Signs. Act Early.\" checklists: things most children (75%) can do by each age. Every child grows at their own pace. If you're worried, don't wait: talk with your pediatrician.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

struct MilestoneRow: View {
    @EnvironmentObject var model: AppModel
    let item: Milestone
    let kidID: String

    var body: some View {
        let status = model.status(item.id, kidID: kidID)
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(MilestoneStatus.allCases) { option in
                    let on = status == option
                    Button {
                        model.setStatus(on ? nil : option, milestoneID: item.id, kidID: kidID)
                    } label: {
                        Text(option.title)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(on ? Color.white : Theme.muted)
                            .background(on ? color(option) : Theme.sunk, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func color(_ status: MilestoneStatus) -> Color {
        switch status {
        case .yes: return Theme.good
        case .notYet: return Theme.warn
        case .unsure: return Theme.muted
        }
    }
}

struct GrowthSection: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    @State private var adding: LogTarget?

    var body: some View {
        let points = Summary.growth(model.state.logs, kidID: kid.id)
        VStack(alignment: .leading, spacing: 14) {
            if points.isEmpty {
                EmptyNote(emoji: "📏", text: "Add weight and height from each checkup to see \(kid.name)'s growth.").card()
            } else {
                chart(title: "Weight", unit: "lb", points: points.compactMap { entry in entry.weightLb.map { (entry.start, $0) } })
                chart(title: "Height", unit: "in", points: points.compactMap { entry in entry.heightIn.map { (entry.start, $0) } })
                VStack(spacing: 0) {
                    ForEach(points.reversed()) { entry in
                        HStack {
                            Text(entry.start.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(entry.detail(now: Date())).font(.subheadline).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { adding = LogTarget(entry: entry, isNew: false) }
                    }
                }
                .card()
            }
            Button {
                let latest = points.last
                adding = LogTarget(entry: LogEntry(kidID: kid.id, kind: .growth, start: Date(), weightLb: latest?.weightLb,
                                                   heightIn: latest?.heightIn, headIn: latest?.headIn), isNew: true)
            } label: {
                Label("Add a measurement", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(item: $adding) { target in
            LogSheet(entry: target.entry, isNew: target.isNew).environmentObject(model)
        }
    }

    @ViewBuilder
    private func chart(title: String, unit: String, points: [(Date, Double)]) -> some View {
        if points.count >= 1 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    if let last = points.last {
                        Text(unit == "lb" ? Measure.pounds(last.1) : Measure.inches(last.1))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.color(kid))
                    }
                }
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Date", point.0), y: .value(title, point.1))
                            .foregroundStyle(Theme.color(kid))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.0), y: .value(title, point.1))
                            .foregroundStyle(Theme.color(kid))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
            }
            .card()
        }
    }
}

struct TipsSection: View {
    @State private var situation: TipSituation?

    var body: some View {
        let today = Tips.ofTheDay(Dates.key(Date()))
        VStack(alignment: .leading, spacing: 14) {
            TipCard(tip: today, label: "Tip of the day")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: situation == nil) { situation = nil }
                    ForEach(TipSituation.allCases) { item in
                        chip("\(item.emoji) \(item.title)", selected: situation == item) { situation = item }
                    }
                }
            }
            ForEach(situation.map { Tips.tips(for: $0) } ?? Tips.all.filter { $0.id != today.id }) { tip in
                TipCard(tip: tip, label: nil)
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Theme.ink)
                .background(selected ? Theme.accent : Theme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? Theme.accent : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct TipCard: View {
    let tip: ParentingTip
    let label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label {
                Text(label)
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.accent)
            }
            Text(tip.title).font(Theme.display(19)).foregroundStyle(Theme.ink)
            HStack(alignment: .top, spacing: 8) {
                Text("Instead of").font(.caption.weight(.bold)).foregroundStyle(Theme.muted).frame(width: 72, alignment: .leading)
                Text(tip.insteadOf).font(.subheadline).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .top, spacing: 8) {
                Text("Try").font(.caption.weight(.bold)).foregroundStyle(Theme.good).frame(width: 72, alignment: .leading)
                Text(tip.tryThis).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            Text(tip.why).font(.caption).foregroundStyle(Theme.muted)
        }
        .card()
    }
}
