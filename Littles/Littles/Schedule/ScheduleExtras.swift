import SwiftUI
import PhotosUI
import Vision
import UniformTypeIdentifiers
import LittlesKit

/// Reads text out of a photo, one line per string.
enum TextReader {
    static func lines(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
        }
    }
}

/// Import no-school days and special days from the school's calendar: an
/// .ics file, a calendar link, or a photo of a printed list.
struct ImportCalendarSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var found: [CalendarImport.Found] = []
    @State private var skipped = Set<String>()
    @State private var kidIDs: [String] = []
    @State private var pickingFile = false
    @State private var photoItem: PhotosPickerItem?
    @State private var working = false
    @State private var message = ""
    @State private var source = "calendar"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { pickingFile = true } label: { Label("Choose an .ics calendar file", systemImage: "doc") }
                    HStack {
                        TextField("Or paste the calendar link (webcal:// or https://)", text: $link)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                        Button("Get") { Task { await fetchLink() } }.disabled(link.isEmpty)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Read a photo of a printed calendar", systemImage: "camera.viewfinder")
                    }
                } header: {
                    Text("From")
                } footer: {
                    Text("Photos work best for lists with one date per line, like \"Nov 27 – No School\".")
                }
                if working {
                    Section { ProgressView() }
                }
                if !message.isEmpty {
                    Section { Text(message).foregroundStyle(Theme.muted) }
                }
                if !found.isEmpty {
                    Section("For") {
                        KidsToggle(kidIDs: $kidIDs)
                    }
                    Section("Found \(found.count)") {
                        ForEach(found) { item in
                            Button {
                                if skipped.contains(item.id) { skipped.remove(item.id) } else { skipped.insert(item.id) }
                            } label: {
                                HStack {
                                    Image(systemName: skipped.contains(item.id) ? "circle" : "checkmark.circle.fill")
                                        .foregroundStyle(skipped.contains(item.id) ? Theme.line : Theme.accent)
                                    VStack(alignment: .leading) {
                                        Text("\(item.kind.emoji) \(item.title)").foregroundStyle(Theme.ink)
                                        Text((Dates.date(item.day)?.formatted(.dateTime.weekday().month().day()) ?? item.day)
                                             + (item.start.map { " · " + Dates.clock($0) } ?? ""))
                                            .font(.caption)
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import a school calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(found.count - skipped.count)") {
                        let chosen = found.filter { !skipped.contains($0.id) }
                        for event in CalendarImport.events(chosen, kidIDs: kidIDs, existing: model.state.events, source: source) {
                            model.saveEvent(event)
                        }
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(found.count == skipped.count)
                }
            }
            .fileImporter(isPresented: $pickingFile, allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data, .calendarEvent, .plainText]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) { show(CalendarImport.ics(text), source: "calendar") }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await readPhoto(item) }
            }
            .onAppear {
                // Preschool events are usually for the preschooler.
                if let older = model.state.kids.max(by: { $0.ageMonths(on: Date()) < $1.ageMonths(on: Date()) }), model.state.kids.count > 1 {
                    kidIDs = [older.id]
                }
            }
        }
    }

    private func show(_ items: [CalendarImport.Found], source: String) {
        let today = Dates.key(Date())
        found = items.filter { $0.day >= today }
        skipped = []
        self.source = source
        message = found.isEmpty ? "Nothing upcoming was found." : ""
    }

    @MainActor
    private func fetchLink() async {
        var text = link.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("webcal://") { text = "https://" + text.dropFirst(9) }
        guard let url = URL(string: text) else { message = "That link doesn't look right."; return }
        working = true
        defer { working = false }
        guard let result = try? await URLSession.shared.data(from: url), let body = String(data: result.0, encoding: .utf8) else {
            message = "Couldn't download that calendar."
            return
        }
        show(CalendarImport.ics(body), source: "calendar")
    }

    @MainActor
    private func readPhoto(_ item: PhotosPickerItem) async {
        working = true
        defer { working = false }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let lines = await TextReader.lines(in: image)
        show(CalendarImport.lines(lines, today: Dates.key(Date())), source: "photo")
    }
}

/// Paste the daily report from daycare or preschool; check the entries; save.
struct DailyReportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var kidID = ""
    @State private var day = Date()

    var body: some View {
        let entries = DailyReport.parse(text, kidID: kidID, day: Dates.key(day))
        NavigationStack {
            Form {
                Section {
                    Picker("Kid", selection: $kidID) {
                        ForEach(model.state.kids) { Text($0.name).tag($0.id) }
                    }
                    DatePicker("Day", selection: $day, displayedComponents: .date)
                }
                Section {
                    TextField("Paste the report: naps, diapers, potty, meals, bottles", text: $text, axis: .vertical)
                        .lineLimit(5...14)
                    if UIPasteboard.general.hasStrings {
                        Button("Paste from clipboard") { text = UIPasteboard.general.string ?? text }
                    }
                } header: {
                    Text("Report")
                } footer: {
                    Text("Works with Brightwheel, Tadpoles and teacher emails: one thing per line, like \"Nap 12:30 – 2:15\".")
                }
                if !entries.isEmpty {
                    Section("Will add \(entries.count)") {
                        ForEach(entries) { entry in
                            TimelineRow(entry: entry, now: Date(), units: model.units)
                        }
                    }
                }
            }
            .navigationTitle("Daily report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        for entry in entries { model.save(entry) }
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(entries.isEmpty)
                }
            }
            .onAppear {
                if kidID.isEmpty { kidID = model.kidID }
            }
        }
    }
}

/// Teachers, the pediatrician, classmates' parents.
struct ContactsSection: View {
    @EnvironmentObject var model: AppModel
    @Binding var editing: Contact?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "People")
                Button { editing = Contact(name: "") } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .accessibilityLabel("Add a person")
            }
            if model.state.contacts.isEmpty {
                EmptyNote(emoji: "👩‍🏫", text: "Add teachers, the pediatrician and classmates' parents for quick calls and texts.").card()
            } else {
                VStack(spacing: 0) {
                    ForEach(model.state.contacts.sorted { $0.name < $1.name }) { contact in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                                Text([contact.role, model.kid(contact.kidID)?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if let phone = URL(string: "tel:" + contact.phone.filter { $0.isNumber || $0 == "+" }), !contact.phone.isEmpty {
                                Link(destination: phone) { Image(systemName: "phone.fill") }
                                if let sms = URL(string: "sms:" + contact.phone.filter { $0.isNumber || $0 == "+" }) {
                                    Link(destination: sms) { Image(systemName: "message.fill") }
                                }
                            }
                            if !contact.email.isEmpty, let mail = URL(string: "mailto:" + contact.email) {
                                Link(destination: mail) { Image(systemName: "envelope.fill") }
                            }
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = contact }
                    }
                }
                .card()
            }
        }
    }
}

struct ContactEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var contact: Contact
    let isNew: Bool

    init(contact: Contact, isNew: Bool) {
        _contact = State(initialValue: contact)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $contact.name)
                    TextField("Role, like Teacher or Pediatrician", text: $contact.role)
                    Picker("For", selection: $contact.kidID) {
                        Text("Everyone").tag("")
                        ForEach(model.state.kids) { Text($0.name).tag($0.id) }
                    }
                }
                Section {
                    TextField("Phone", text: $contact.phone).keyboardType(.phonePad)
                    TextField("Email", text: $contact.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Note", text: $contact.note, axis: .vertical)
                }
                if !isNew {
                    Section {
                        Button("Delete", role: .destructive) {
                            model.deleteContact(contact.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New person" : contact.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveContact(contact)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(contact.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Groceries from the meal plan, school supplies, party gifts.
struct ShoppingSection: View {
    @EnvironmentObject var model: AppModel
    @State private var newItem = ""
    @State private var list = "School"

    private let lists = ["Groceries", "School", "Party", "Other"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "To buy")
                if model.state.shopping.contains(where: { $0.done }) {
                    Button("Clear bought") { model.clearBought() }.font(.subheadline)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Add something", text: $newItem)
                        .onSubmit(add)
                    Picker("List", selection: $list) {
                        ForEach(lists, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Button(action: add) { Image(systemName: "plus.circle.fill").font(.title3) }
                        .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(lists, id: \.self) { name in
                    let items = model.state.shopping.filter { $0.list == name || (name == "Other" && !lists.dropLast().contains($0.list)) }
                    if !items.isEmpty {
                        Text(name).font(.caption.weight(.bold)).foregroundStyle(Theme.muted).padding(.top, 4)
                        ForEach(items) { item in
                            Button { model.toggleShopping(item.id) } label: {
                                Label(item.title, systemImage: item.done ? "checkmark.circle.fill" : "circle")
                                    .strikethrough(item.done)
                                    .foregroundStyle(item.done ? Theme.muted : Theme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .card()
        }
    }

    private func add() {
        model.addShopping(newItem, list: list)
        newItem = ""
    }
}
