import SwiftUI
import UniformTypeIdentifiers
import LittlesKit

/// The kids (names, birthdays, colors) and app-wide settings.
struct FamilyView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Kid?
    @State private var exportURL: URL?
    @State private var syncURL: URL?
    @State private var importingSync = false
    @State private var editingChart: RoutineChart?

    var body: some View {
        NavigationStack {
            List {
                Section("Kids") {
                    ForEach(model.state.kids) { kid in
                        Button { editing = kid } label: {
                            HStack(spacing: 12) {
                                KidBadge(kid: kid, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kid.name).font(.headline).foregroundStyle(Theme.ink)
                                    Text(kid.birthday.isEmpty ? "Add a birthday"
                                         : "\(kid.ageLabel(on: Date())) · born \(Dates.date(kid.birthday)?.formatted(date: .abbreviated, time: .omitted) ?? kid.birthday)")
                                        .font(.subheadline)
                                        .foregroundStyle(kid.birthday.isEmpty ? Theme.warn : Theme.muted)
                                }
                            }
                        }
                    }
                    Button {
                        editing = Kid(name: "", birthday: Dates.key(Date()), color: model.state.kids.count % Theme.kidColors.count)
                    } label: {
                        Label("Add a kid", systemImage: "plus")
                    }
                }
                Section {
                    if let syncURL {
                        ShareLink(item: syncURL) {
                            Label("Send to the other phone", systemImage: "iphone.and.arrow.forward")
                        }
                    } else {
                        Button {
                            syncURL = model.syncFileURL()
                        } label: {
                            Label("Make a sync file", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    Button {
                        importingSync = true
                    } label: {
                        Label("Merge a file from the other phone", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Share with your partner or a sitter")
                } footer: {
                    Text("Send the sync file by AirDrop or Messages and open it in Littles on the other phone. Both phones end up with everything; the newer copy of an entry wins and deletions carry over. Do it both ways to stay matched.")
                }
                SettingsSections()
                Section {
                    ForEach(model.state.charts) { chart in
                        Button { editingChart = chart } label: {
                            HStack {
                                Text("\(chart.emoji) \(chart.title)").foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(chart.steps.count) steps · \(model.names(chart.kidIDs))").font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    Button {
                        editingChart = RoutineChart(title: "", emoji: "✅", steps: [ChartStep(emoji: "⭐️", title: "")])
                    } label: {
                        Label("Add a chart", systemImage: "plus")
                    }
                } header: {
                    Text("Picture charts")
                } footer: {
                    Text("Bedtime, morning or any routine. Kids tap each step on Today.")
                }
                Section("Reports for the pediatrician") {
                    ForEach(model.state.kids) { kid in
                        ReportButton(kid: kid)
                    }
                }
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share the export file", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            exportURL = model.exportURL()
                        } label: {
                            Label("Export everything (JSON)", systemImage: "doc.badge.arrow.up")
                        }
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything stays on this iPhone. Export makes a file you can save to Files or send to the pediatrician.")
                }
                Section("About") {
                    Text("Littles brings a baby log, a first-foods guide, things to do, the preschool schedule and milestones together for the whole family. Food and milestone guidance is general information, not medical advice.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { kid in
                KidEditor(kid: kid, isNew: model.kid(kid.id) == nil).environmentObject(model)
            }
            .sheet(item: $editingChart) { chart in
                ChartEditor(chart: chart, isNew: !model.state.charts.contains { $0.id == chart.id }).environmentObject(model)
            }
            .fileImporter(isPresented: $importingSync, allowedContentTypes: [UTType(exportedAs: "com.steveburlison.littles.family"), .json, .data]) { result in
                if case .success(let url) = result { model.importSync(from: url) }
            }
        }
    }
}

struct KidEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var kid: Kid
    let isNew: Bool
    @State private var confirmDelete = false

    init(kid: Kid, isNew: Bool) {
        _kid = State(initialValue: kid)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        KidBadge(kid: kid, size: 72)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Name", text: $kid.name)
                    BirthdayPicker(birthday: $kid.birthday)
                    Picker("Sex (for growth charts)", selection: $kid.sex) {
                        Text("Not set").tag("")
                        Text("Boy").tag("boy")
                        Text("Girl").tag("girl")
                    }
                    TextField("Emoji (optional)", text: Binding(get: { kid.emoji }, set: { kid.emoji = String($0.prefix(2)) }))
                }
                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(Theme.kidColors.indices, id: \.self) { index in
                            Button { kid.color = index } label: {
                                Circle()
                                    .fill(Theme.kidColors[index])
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Theme.ink, lineWidth: kid.color == index ? 3 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !isNew && model.state.kids.count > 1 {
                    Section {
                        Button("Remove \(kid.name)", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "Add a kid" : kid.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = kid
                        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                        model.saveKid(saved)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(kid.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Remove \(kid.name) and everything logged for them?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.deleteKid(kid.id)
                    dismiss()
                }
            }
        }
    }
}

struct BirthdayPicker: View {
    @Binding var birthday: String

    var body: some View {
        DatePicker("Birthday", selection: Binding(
            get: { Dates.date(birthday) ?? Date() },
            set: { birthday = Dates.key($0) }
        ), in: ...Date(), displayedComponents: .date)
    }
}

/// First launch: confirm the kids' names and set their birthdays, since
/// everything (foods, activities, milestones) depends on age.
struct WelcomeView: View {
    @EnvironmentObject var model: AppModel
    let onDone: () -> Void
    @State private var kids: [Kid] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("👶🧒").font(.system(size: 52))
                        Text("Welcome to Littles")
                            .font(Theme.display(32))
                            .foregroundStyle(Theme.ink)
                        Text("One place for bottles, diapers and naps, what to feed them, things to do together, the preschool schedule and milestones. Start with birthdays: everything adjusts to each kid's age.")
                            .font(.body)
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach($kids) { $kid in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                KidBadge(kid: kid, size: 40)
                                TextField("Name", text: $kid.name)
                                    .font(.title3.weight(.bold))
                            }
                            BirthdayPicker(birthday: $kid.birthday)
                        }
                        .card()
                    }
                    Button {
                        for var kid in kids {
                            kid.name = kid.name.trimmingCharacters(in: .whitespaces)
                            if kid.birthday.isEmpty { kid.birthday = Dates.key(Date()) }
                            model.saveKid(kid)
                        }
                        model.state.onboarded = true
                        onDone()
                    } label: {
                        Text("Let's go")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(kids.contains { $0.name.trimmingCharacters(in: .whitespaces).isEmpty })
                    Text("Everything stays on this iPhone. You can add a kid or change birthdays later from the Family button on Today.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.bg.ignoresSafeArea())
        }
        .onAppear {
            kids = model.state.kids.map { kid in
                var copy = kid
                // Show a starting date in the picker so "Let's go" never saves an empty birthday.
                if copy.birthday.isEmpty { copy.birthday = Dates.key(Date()) }
                return copy
            }
        }
        .interactiveDismissDisabled()
    }
}
