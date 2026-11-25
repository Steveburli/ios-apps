import SwiftUI
import ThoughtsKit

/// The properties at the top of a database row's page.
struct RowProperties: View {
    @Environment(AppModel.self) private var model
    let rowID: UUID
    let databaseID: UUID
    @State private var editingColumns = false

    var body: some View {
        let properties = model.page(databaseID)?.database?.properties ?? []
        VStack(alignment: .leading, spacing: 2) {
            ForEach(properties) { property in
                HStack(alignment: .center, spacing: 10) {
                    Label(property.name, systemImage: property.type.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .frame(width: 118, alignment: .leading)
                    PropertyValueControl(rowID: rowID, databaseID: databaseID, property: property)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 36)
            }
            Button { editingColumns = true } label: {
                Label("Edit properties", systemImage: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.faint)
                    .frame(minHeight: 34)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $editingColumns) {
            ColumnsSheet(databaseID: databaseID)
        }
    }
}

/// Edits one value of one row.
struct PropertyValueControl: View {
    @Environment(AppModel.self) private var model
    let rowID: UUID
    let databaseID: UUID
    let property: PropertyDefinition
    @State private var addingOption = false
    @State private var newOption = ""

    private var value: PropertyValue? {
        model.page(rowID)?.value(property.id)
    }

    private var numberValue: Double? {
        if case .number(let n)? = value { return n }
        return nil
    }

    private func set(_ value: PropertyValue?) {
        model.setValue(value, row: rowID, property: property.id)
    }

    var body: some View {
        control
            .alert("New option", isPresented: $addingOption) {
                TextField("Name", text: $newOption)
                Button("Add") {
                    if let option = model.addOption(newOption, to: property.id, in: databaseID) {
                        if property.type == .multiSelect {
                            set(.multiSelect((value?.optionIDs ?? []) + [option.id]))
                        } else {
                            set(.select(option.id))
                        }
                    }
                    newOption = ""
                }
                Button("Cancel", role: .cancel) { newOption = "" }
            }
    }

    @ViewBuilder private var control: some View {
        switch property.type {
        case .text:
            TextField("Empty", text: Binding(
                get: { if case .text(let s)? = value { return s } else { return "" } },
                set: { set(.text($0)) }
            ), axis: .vertical)
            .font(.system(size: 15))
        case .url:
            HStack {
                TextField("Empty", text: Binding(
                    get: { if case .url(let s)? = value { return s } else { return "" } },
                    set: { set(.url($0)) }
                ))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                if case .url(let s)? = value, let url = URL(string: s.hasPrefix("http") ? s : "https://" + s) {
                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                }
            }
        case .number:
            NumberField(value: numberValue, onCommit: { number in set(number.map { PropertyValue.number($0) }) })
        case .checkbox:
            let on = value == .checkbox(true)
            Button { set(.checkbox(!on)) } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(on ? Theme.accent : Theme.faint)
            }
            .buttonStyle(.plain)
        case .date:
            if case .date(let date)? = value {
                HStack(spacing: 6) {
                    DatePicker("", selection: Binding(get: { date }, set: { set(.date($0)) }), displayedComponents: .date)
                        .labelsHidden()
                    Button { set(nil) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear date")
                }
            } else {
                Button("Empty") { set(.date(Calendar.current.startOfDay(for: Date()))) }
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.faint)
                    .buttonStyle(.plain)
            }
        case .select:
            Menu {
                ForEach(property.options) { option in
                    Button { set(.select(option.id)) } label: {
                        CheckLabel(title: option.name, on: value?.selectID == option.id)
                    }
                }
                Divider()
                Button { addingOption = true } label: { Label("New option…", systemImage: "plus") }
                if value != nil {
                    Button(role: .destructive) { set(nil) } label: { Label("Clear", systemImage: "xmark") }
                }
            } label: {
                PropertyValueView(value: value, property: property, emptyText: "Empty")
            }
        case .multiSelect:
            Menu {
                ForEach(property.options) { option in
                    let chosen = value?.optionIDs ?? []
                    Button {
                        if chosen.contains(option.id) {
                            set(.multiSelect(chosen.filter { $0 != option.id }))
                        } else {
                            set(.multiSelect(chosen + [option.id]))
                        }
                    } label: {
                        CheckLabel(title: option.name, on: chosen.contains(option.id))
                    }
                }
                Divider()
                Button { addingOption = true } label: { Label("New option…", systemImage: "plus") }
            } label: {
                PropertyValueView(value: value, property: property, emptyText: "Empty")
            }
        }
    }
}

/// A number field that keeps what you type ("2.") until it's a number.
struct NumberField: View {
    let value: Double?
    let onCommit: (Double?) -> Void
    @State private var text = ""

    var body: some View {
        TextField("Empty", text: $text)
            .keyboardType(.decimalPad)
            .font(.system(size: 15))
            .onAppear { text = value.map(Workspace.format(number:)) ?? "" }
            .onChange(of: text) { _, newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                if trimmed.isEmpty {
                    onCommit(nil)
                } else if let number = Double(trimmed) {
                    onCommit(number)
                }
            }
    }
}

/// Edits a table cell in a small sheet.
struct CellEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cell: CellRef

    var body: some View {
        NavigationStack {
            Form {
                if let property = model.page(cell.databaseID)?.database?.property(cell.propertyID) {
                    Section {
                        PropertyValueControl(rowID: cell.rowID, databaseID: cell.databaseID, property: property)
                    } header: {
                        Label(property.name, systemImage: property.type.symbol)
                    }
                }
            }
            .navigationTitle(model.page(cell.rowID)?.displayTitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// The database's properties: add, rename, change type, reorder, delete, and edit options.
struct ColumnsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let databaseID: UUID

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.page(databaseID)?.database?.properties ?? []) { property in
                        NavigationLink {
                            PropertyEditor(databaseID: databaseID, propertyID: property.id)
                        } label: {
                            Label(property.name, systemImage: property.type.symbol)
                        }
                    }
                    .onDelete { offsets in
                        let properties = model.page(databaseID)?.database?.properties ?? []
                        model.mutate { w in
                            for i in offsets { w.deleteProperty(properties[i].id, in: databaseID) }
                        }
                    }
                    .onMove { from, to in
                        model.updateSchema(databaseID) { $0.properties.move(fromOffsets: from, toOffset: to) }
                    }
                } header: {
                    Text("Properties")
                } footer: {
                    Text("Every row has a Name. Swipe to delete a property; its values go with it.")
                }
                Section {
                    Menu {
                        ForEach(PropertyType.allCases, id: \.self) { type in
                            Button {
                                model.mutate { $0.addProperty(to: databaseID, name: type.displayName, type: type) }
                            } label: {
                                Label(type.displayName, systemImage: type.symbol)
                            }
                        }
                    } label: {
                        Label("Add a property", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Properties")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct PropertyEditor: View {
    @Environment(AppModel.self) private var model
    let databaseID: UUID
    let propertyID: UUID

    var body: some View {
        if let property = model.page(databaseID)?.database?.property(propertyID) {
            Form {
                Section("Name") {
                    TextField("Name", text: Binding(
                        get: { property.name },
                        set: { name in model.updateProperty(databaseID, propertyID) { $0.name = name } }
                    ))
                }
                Section {
                    Picker("Type", selection: Binding(
                        get: { property.type },
                        set: { type in model.mutate { $0.changePropertyType(propertyID, in: databaseID, to: type) } }
                    )) {
                        ForEach(PropertyType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.symbol).tag(type)
                        }
                    }
                } footer: {
                    Text("Values are converted where they can be: text becomes options, options become text.")
                }
                if property.type.hasOptions {
                    Section("Options") {
                        ForEach(property.options) { option in
                            HStack {
                                Menu {
                                    ForEach(TagColor.allCases, id: \.self) { color in
                                        Button(color.name) { setOption(option.id) { $0.color = color } }
                                    }
                                } label: {
                                    Circle().fill(option.color.ink).frame(width: 14, height: 14)
                                        .padding(6)
                                }
                                .accessibilityLabel("Color: \(option.color.name)")
                                TextField("Option", text: Binding(
                                    get: { option.name },
                                    set: { name in setOption(option.id) { $0.name = name } }
                                ))
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { property.options[$0].id }
                            model.mutate { w in
                                for id in ids { w.deleteOption(id, of: propertyID, in: databaseID) }
                            }
                        }
                        .onMove { from, to in
                            model.updateProperty(databaseID, propertyID) { $0.options.move(fromOffsets: from, toOffset: to) }
                        }
                        Button {
                            model.addOption("Option \(property.options.count + 1)", to: propertyID, in: databaseID)
                        } label: {
                            Label("Add an option", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle(property.name)
        }
    }

    private func setOption(_ optionID: UUID, _ body: (inout SelectOption) -> Void) {
        model.updateProperty(databaseID, propertyID) { property in
            guard let i = property.options.firstIndex(where: { $0.id == optionID }) else { return }
            body(&property.options[i])
        }
    }
}
