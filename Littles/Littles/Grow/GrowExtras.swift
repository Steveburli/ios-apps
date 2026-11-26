import SwiftUI
import UIKit
import LittlesKit

/// Turns the report's web page into a PDF file to share.
enum ReportPDF {
    @MainActor
    static func make(html: String, name: String) -> URL? {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        renderer.setValue(NSValue(cgRect: page), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: page.insetBy(dx: 30, dy: 36)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }
}

/// A button that makes the two-week pediatrician report and shares it.
struct ReportButton: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    @State private var url: URL?

    var body: some View {
        if let url {
            ShareLink(item: url) {
                Label("Share \(kid.name)'s report (PDF)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                let html = PediatricianReport.html(kid: kid, state: model.state, now: Date())
                url = ReportPDF.make(html: html, name: "\(kid.name) report \(Dates.key(Date())).pdf")
            } label: {
                Label("Make a report for the pediatrician", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Vaccines, checkups, teeth, the sick log, and the report for the doctor.
struct HealthSection: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    @State private var adding: LogTarget?
    @State private var showAllShots = false

    var body: some View {
        let age = kid.ageMonths(on: Date())
        let today = Dates.key(Date())
        let given = model.state.vaccines[kid.id] ?? [:]
        VStack(alignment: .leading, spacing: 14) {
            ReportButton(kid: kid)
            if let next = HealthSchedule.nextCheckup(birthday: kid.birthday, today: today) {
                HStack(spacing: 12) {
                    Text("🩺").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next checkup").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                        Text("\(next.0.title) visit").font(.headline)
                        Text("Around \(Dates.date(next.1)?.formatted(date: .long, time: .omitted) ?? next.1)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .card()
            }
            vaccines(age: age, given: given)
            teeth
            sickLog
            Text("Schedules follow the CDC and AAP as of 2025 and can change; some doses depend on the brand or your child's health. Your pediatrician's plan comes first.")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .sheet(item: $adding) { target in
            LogSheet(entry: target.entry, isNew: target.isNew).environmentObject(model)
        }
    }

    private func vaccines(age: Int, given: [String: String]) -> some View {
        let doses = HealthSchedule.doses.filter { showAllShots || $0.fromMonths <= age + 6 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("💉 Vaccines").font(.headline)
                Spacer()
                Button(showAllShots ? "Show fewer" : "Show all") { showAllShots.toggle() }.font(.subheadline)
            }
            ForEach(doses) { dose in
                let state = HealthSchedule.state(dose, ageMonths: age, given: given)
                Button {
                    if case .given = state {
                        model.setVaccine(dose.id, kidID: kid.id, day: nil)
                    } else {
                        model.setVaccine(dose.id, kidID: kid.id, day: Dates.key(Date()))
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(state))
                            .foregroundStyle(color(state))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(dose.short) \(dose.dose)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(dose.vaccine + (dose.note.isEmpty ? "" : " · \(dose.note)")).font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(label(state, dose)).font(.caption.weight(.semibold)).foregroundStyle(color(state))
                    }
                }
                .buttonStyle(.plain)
            }
            Text("Tap a dose to mark it given today; tap again to undo.").font(.caption2).foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func icon(_ state: HealthSchedule.DoseState) -> String {
        switch state {
        case .given: return "checkmark.circle.fill"
        case .due: return "circle.lefthalf.filled"
        case .overdue: return "exclamationmark.circle.fill"
        case .upcoming: return "circle"
        }
    }

    private func color(_ state: HealthSchedule.DoseState) -> Color {
        switch state {
        case .given: return Theme.good
        case .due: return Theme.accent
        case .overdue: return Theme.warn
        case .upcoming: return Theme.muted
        }
    }

    private func label(_ state: HealthSchedule.DoseState, _ dose: VaccineDose) -> String {
        switch state {
        case .given(let day): return Dates.date(day)?.formatted(.dateTime.month(.abbreviated).day().year()) ?? day
        case .due: return "Due now"
        case .overdue: return "Ask about it"
        case .upcoming: return dose.fromMonths == dose.toMonths ? Age.short(months: dose.fromMonths) : "\(Age.short(months: dose.fromMonths))–\(Age.short(months: dose.toMonths))"
        }
    }

    private var teeth: some View {
        let count = Teeth.count(model.state.logs, kidID: kid.id)
        let streak = Teeth.brushStreak(model.state.logs, kidID: kid.id, today: Dates.key(Date()))
        return HStack(spacing: 12) {
            Text("🦷").font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(count == 1 ? "1 tooth" : "\(count) teeth")
                    .font(.headline)
                Text(streak > 0 ? "Brushed \(streak) day\(streak == 1 ? "" : "s") in a row" : "Log brushing on Today to start a streak")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("New tooth") {
                adding = LogTarget(entry: LogEntry(kidID: kid.id, kind: .tooth, start: Date()), isNew: true)
            }
            .buttonStyle(.bordered)
        }
        .card()
    }

    private var sickLog: some View {
        let entries = model.state.logs
            .filter { $0.kidID == kid.id && [.symptom, .temperature, .meds].contains($0.kind) }
            .sorted { $0.start > $1.start }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🤒 Sick log").font(.headline)
                Spacer()
                Button("Log symptoms") {
                    adding = LogTarget(entry: LogEntry(kidID: kid.id, kind: .symptom, start: Date()), isNew: true)
                }
                .font(.subheadline)
            }
            if entries.isEmpty {
                Text("Nothing logged. Fevers, symptoms and medicine show up here.").font(.subheadline).foregroundStyle(Theme.muted)
            }
            ForEach(entries.prefix(12)) { entry in
                TimelineRow(entry: entry, now: Date(), units: model.units)
                    .contentShape(Rectangle())
                    .onTapGesture { adding = LogTarget(entry: entry, isNew: false) }
            }
        }
        .card()
    }
}

/// Firsts, quotes and photos, and a monthly recap to share.
struct MemoriesSection: View {
    @EnvironmentObject var model: AppModel
    let kid: Kid
    @State private var monthOffset = 0
    @State private var adding: LogTarget?
    @State private var shareImage: UIImage?

    var body: some View {
        let month = monthKey
        let recap = Recap.month(month, kid: kid, state: model.state)
        let memories = Recap.memories(model.state.logs, kidID: kid.id)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button("Add a first") {
                    adding = LogTarget(entry: LogEntry(kidID: kid.id, kind: .first, start: Date()), isNew: true)
                }
                .buttonStyle(.borderedProminent)
                Button("Save a quote") {
                    adding = LogTarget(entry: LogEntry(kidID: kid.id, kind: .quote, start: Date()), isNew: true)
                }
                .buttonStyle(.bordered)
            }
            HStack {
                Button { monthOffset -= 1; shareImage = nil } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text("Monthly recap").font(.headline)
                Spacer()
                Button { monthOffset += 1; shareImage = nil } label: { Image(systemName: "chevron.right") }
                    .disabled(monthOffset >= 0)
            }
            RecapCard(kid: kid, recap: recap, units: model.units, photo: recap.photos.last.flatMap { model.photo($0) })
            if let shareImage {
                ShareLink(item: Image(uiImage: shareImage), preview: SharePreview("\(kid.name) · \(recap.title)", image: Image(uiImage: shareImage))) {
                    Label("Send to the grandparents", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    let renderer = ImageRenderer(content: RecapCard(kid: kid, recap: recap, units: model.units,
                                                                    photo: recap.photos.last.flatMap { model.photo($0) })
                        .frame(width: 380)
                        .padding(16)
                        .background(Color(hex: 0xFBF7F0)))
                    renderer.scale = 3
                    shareImage = renderer.uiImage
                } label: {
                    Label("Make a picture to share", systemImage: "photo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            SectionTitle(text: "Firsts, quotes and photos")
            if memories.isEmpty {
                EmptyNote(emoji: "⭐️", text: "Firsts, funny quotes and photos from any log entry collect here.").card()
            }
            ForEach(memories) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(entry.kind.isMemory ? entry.kind.emoji : "📷")
                        Text(entry.start.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.muted)
                    }
                    if !entry.note.isEmpty {
                        Text(entry.note).font(entry.kind == .quote ? .body.italic() : .body).foregroundStyle(Theme.ink)
                    } else if !entry.kind.isMemory {
                        Text("\(entry.kind.title) · \(entry.detail(now: Date(), units: model.units))").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    if let image = model.photo(entry.photo) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .card()
                .onTapGesture { adding = LogTarget(entry: entry, isNew: false) }
            }
        }
        .sheet(item: $adding) { target in
            LogSheet(entry: target.entry, isNew: target.isNew).environmentObject(model)
        }
    }

    private var monthKey: String {
        let date = Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
        return String(Dates.key(date).prefix(7))
    }
}

/// The recap as a card: also rendered to a picture for sharing.
struct RecapCard: View {
    let kid: Kid
    let recap: Recap.Month
    let units: Units
    let photo: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                KidBadge(kid: kid, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(kid.name)'s \(recap.title)").font(Theme.display(20)).foregroundStyle(Color(hex: 0x2B2420))
                    Text(kid.ageLabel(on: Date())).font(.subheadline).foregroundStyle(Color(hex: 0x786C62))
                }
            }
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            ForEach(recap.firsts, id: \.self) { line("⭐️", $0) }
            ForEach(recap.quotes, id: \.self) { line("💬", $0) }
            if !recap.newFoods.isEmpty {
                line("🥑", "\(recap.newFoods.count) new food\(recap.newFoods.count == 1 ? "" : "s"): " + recap.newFoods.prefix(8).joined(separator: ", ")
                     + (recap.newFoods.count > 8 ? "…" : ""))
            }
            if let loved = recap.lovedFood { line("😍", "Favorite: \(loved)") }
            if let gain = recap.weightChange { line("⚖️", "Grew \(gain >= 0 ? "+" : "")\(units.isMetric ? String(format: "%.2f kg", gain * Units.kgPerLb) : String(format: "%.1f lb", gain))") }
            if let height = recap.heightChange { line("📏", "\(height >= 0 ? "+" : "")\(units.isMetric ? String(format: "%.1f cm", height * Units.cmPerIn) : String(format: "%.1f in", height)) taller") }
            if recap.activities > 0 { line("🧸", "\(recap.activities) activit\(recap.activities == 1 ? "y" : "ies") together") }
            if recap.milestonesDone > 0 { line("🎯", "\(recap.milestonesDone) milestones checked off") }
            if recap.firsts.isEmpty && recap.quotes.isEmpty && recap.newFoods.isEmpty && recap.weightChange == nil {
                Text("Nothing logged this month yet.").font(.subheadline).foregroundStyle(Color(hex: 0x786C62))
            }
            Text("Made with Littles").font(.caption2).foregroundStyle(Color(hex: 0x786C62))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Color(hex: 0xEADFD1), lineWidth: 1))
    }

    private func line(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(emoji)
            Text(text).font(.subheadline).foregroundStyle(Color(hex: 0x2B2420))
        }
    }
}
