import SwiftUI
import ThoughtsKit

/// A database's rows as a table, board or list, with the view switcher, sort, filter and columns.
struct DatabaseBody: View {
    @Environment(AppModel.self) private var model
    let databaseID: UUID
    @State private var editingColumns = false
    @State private var editingCell: CellRef?

    var body: some View {
        if let schema = model.page(databaseID)?.database {
            VStack(alignment: .leading, spacing: 12) {
                viewBar(schema)
                    .padding(.horizontal, 20)
                switch schema.layout {
                case .table:
                    TableLayout(databaseID: databaseID, schema: schema, editingCell: $editingCell)
                case .board:
                    BoardLayout(databaseID: databaseID, schema: schema)
                case .list:
                    ListLayout(databaseID: databaseID, schema: schema)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 40)
            .sheet(isPresented: $editingColumns) {
                ColumnsSheet(databaseID: databaseID)
            }
            .sheet(item: $editingCell) { cell in
                CellEditorSheet(cell: cell)
                    .presentationDetents([.height(300), .medium])
            }
        }
    }

    private func viewBar(_ schema: DatabaseSchema) -> some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Layout", selection: Binding(
                    get: { schema.layout },
                    set: { layout in model.updateSchema(databaseID) { $0.layout = layout } }
                )) {
                    ForEach(DatabaseLayout.allCases, id: \.self) { layout in
                        Label(layout.displayName, systemImage: layout.symbol).tag(layout)
                    }
                }
                if schema.layout == .board {
                    let selects = schema.properties.filter { $0.type == .select }
                    if selects.count > 1 {
                        Picker("Group by", selection: Binding(
                            get: { schema.groupProperty?.id },
                            set: { id in model.updateSchema(databaseID) { $0.groupByID = id } }
                        )) {
                            ForEach(selects) { property in
                                Text(property.name).tag(Optional(property.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            } label: {
                pill(schema.layout.symbol, schema.layout.displayName, active: true)
            }
            SortMenu(databaseID: databaseID, schema: schema)
            FilterMenu(databaseID: databaseID, schema: schema)
            Spacer()
            Button { editingColumns = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(Theme.muted)
                    .frame(width: 34, height: 30)
            }
            .accessibilityLabel("Properties")
            Button {
                model.open(model.addRow(to: databaseID))
            } label: {
                Text("New")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

func pill(_ symbol: String, _ title: String, active: Bool) -> some View {
    HStack(spacing: 5) {
        Image(systemName: symbol).font(.system(size: 12))
        Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
    }
    .foregroundStyle(active ? Theme.accent : Theme.muted)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(active ? Theme.accentSoft : Theme.sunk, in: Capsule())
}

struct SortMenu: View {
    @Environment(AppModel.self) private var model
    let databaseID: UUID
    let schema: DatabaseSchema

    var body: some View {
        Menu {
            Picker("Sort by", selection: Binding(
                get: { schema.sort.key },
                set: { key in model.updateSchema(databaseID) { $0.sort.key = key } }
            )) {
                Text("Manual").tag(SortKey.manual)
                Text("Name").tag(SortKey.title)
                Text("Created").tag(SortKey.created)
                Text("Edited").tag(SortKey.edited)
                ForEach(schema.properties) { property in
                    Text(property.name).tag(SortKey.property(property.id))
                }
            }
            if schema.sort.key != .manual {
                Picker("Direction", selection: Binding(
                    get: { schema.sort.ascending },
                    set: { up in model.updateSchema(databaseID) { $0.sort.ascending = up } }
                )) {
                    Label("Ascending", systemImage: "arrow.up").tag(true)
                    Label("Descending", systemImage: "arrow.down").tag(false)
                }
            }
        } label: {
            pill("arrow.up.arrow.down", sortName, active: schema.sort.key != .manual)
        }
    }

    private var sortName: String {
        switch schema.sort.key {
        case .manual: return "Sort"
        case .title: return "Name"
        case .created: return "Created"
        case .edited: return "Edited"
        case .property(let id): return schema.property(id)?.name ?? "Sort"
        }
    }
}

struct FilterMenu: View {
    @Environment(AppModel.self) private var model
    let databaseID: UUID
    let schema: DatabaseSchema

    var body: some View {
        let filterable = schema.properties.filter { $0.type.hasOptions || $0.type == .checkbox }
        Menu {
            Button {
                model.updateSchema(databaseID) { $0.filter = nil }
            } label: {
                CheckLabel(title: "Show everything", on: schema.filter == nil)
            }
            ForEach(filterable) { property in
                Menu(property.name) {
                    if property.type == .checkbox {
                        ForEach([true, false], id: \.self) { want in
                            Button {
                                model.updateSchema(databaseID) {
                                    $0.filter = DatabaseFilter(propertyID: property.id, checked: want)
                                }
                            } label: {
                                CheckLabel(title: want ? "Ticked" : "Not ticked", on: isActive(property, checked: want))
                            }
                        }
                    } else {
                        ForEach(property.options) { option in
                            Button { toggle(option.id, of: property) } label: {
                                CheckLabel(title: option.name, on: isActive(property, option: option.id))
                            }
                        }
                    }
                }
            }
        } label: {
            pill("line.3.horizontal.decrease", filterName, active: schema.filter != nil)
        }
        .disabled(filterable.isEmpty)
    }

    private var filterName: String {
        guard let filter = schema.filter, let property = schema.property(filter.propertyID) else { return "Filter" }
        if let checked = filter.checked { return "\(property.name): \(checked ? "Yes" : "No")" }
        let names = filter.optionIDs.compactMap { property.option($0)?.name }
        return names.count == 1 ? names[0] : "\(property.name) (\(names.count))"
    }

    private func isActive(_ property: PropertyDefinition, option: UUID? = nil, checked: Bool? = nil) -> Bool {
        guard let filter = schema.filter, filter.propertyID == property.id else { return false }
        if let checked { return filter.checked == checked }
        if let option { return filter.optionIDs.contains(option) }
        return false
    }

    private func toggle(_ optionID: UUID, of property: PropertyDefinition) {
        model.updateSchema(databaseID) { schema in
            var filter = schema.filter?.propertyID == property.id ? schema.filter! : DatabaseFilter(propertyID: property.id)
            if let i = filter.optionIDs.firstIndex(of: optionID) {
                filter.optionIDs.remove(at: i)
            } else {
                filter.optionIDs.append(optionID)
            }
            schema.filter = filter.optionIDs.isEmpty ? nil : filter
        }
    }
}

/// A menu item with a check mark when it's on.
struct CheckLabel: View {
    let title: String
    let on: Bool

    var body: some View {
        if on {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

/// A cell being edited: which row and which property.
struct CellRef: Identifiable, Hashable {
    let rowID: UUID
    let databaseID: UUID
    let propertyID: UUID

    var id: String { rowID.uuidString + propertyID.uuidString }
}

// MARK: - Table

struct TableLayout: View {
    @Environment(AppModel.self) private var model
    let databaseID: UUID
    let schema: DatabaseSchema
    @Binding var editingCell: CellRef?

    static let nameWidth: CGFloat = 190

    static func width(_ type: PropertyType) -> CGFloat {
        switch type {
        case .checkbox: return 90
        case .number: return 100
        case .date: return 130
        case .select: return 140
        case .multiSelect, .url, .text: return 170
        }
    }

    var body: some View {
        let rows = model.workspace.rows(of: databaseID)
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    header("textformat", "Name", width: TableLayout.nameWidth)
                    ForEach(schema.properties) { property in
                        header(property.type.symbol, property.name, width: TableLayout.width(property.type))
                    }
                }
                .background(Theme.paper)
                Rectangle().fill(Theme.line).frame(height: 1)
                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        NavigationLink(value: row.id) {
                            HStack(spacing: 6) {
                                if row.icon != nil { PageIcon(page: row, size: 14) }
                                Text(row.displayTitle)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(row.title.isEmpty ? Theme.muted : Theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .frame(width: TableLayout.nameWidth, height: 42, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
                        ForEach(schema.properties) { property in
                            cell(row, property)
                        }
                    }
                    .contextMenu { RowMenuItems(rowID: row.id) }
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                Button {
                    model.open(model.addRow(to: databaseID))
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8)
                        .frame(height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text("\(rows.count) \(rows.count == 1 ? "row" : "rows")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 12)
        }
    }

    private func header(_ symbol: String, _ title: String, width: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11))
            Text(title).lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 8)
        .frame(width: width, height: 34, alignment: .leading)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private func cell(_ row: Page, _ property: PropertyDefinition) -> some View {
        Group {
            if property.type == .checkbox {
                let on = row.value(property.id) == .checkbox(true)
                Button {
                    model.setValue(.checkbox(!on), row: row.id, property: property.id)
                } label: {
                    Image(systemName: on ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18))
                        .foregroundStyle(on ? Theme.accent : Theme.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    editingCell = CellRef(rowID: row.id, databaseID: databaseID, propertyID: property.id)
                } label: {
                    PropertyValueView(value: row.value(property.id), property: property)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: TableLayout.width(property.type), height: 42)
        .clipped()
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }
}

struct RowMenuItems: View {
    @Environment(AppModel.self) private var model
    let rowID: UUID

    var body: some View {
        Button { model.open(rowID) } label: { Label("Open", systemImage: "arrow.up.left.and.arrow.down.right") }
        Button { model.duplicate(rowID) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button(role: .destructive) { model.trash(rowID) } label: { Label("Delete", systemImage: "trash") }
    }
}

/// A value shown read-only: chips for options, a formatted date, and so on.
struct PropertyValueView: View {
    let value: PropertyValue?
    let property: PropertyDefinition
    var emptyText: String = ""

    var body: some View {
        switch value {
        case .select(let id)?:
            if let option = property.option(id) { TagChip(option: option) } else { empty }
        case .multiSelect(let ids)?:
            HStack(spacing: 4) {
                ForEach(ids.compactMap { property.option($0) }) { TagChip(option: $0) }
            }
        case .date(let date)?:
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
        case .checkbox(let on)?:
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .foregroundStyle(on ? Theme.accent : Theme.faint)
        case .url(let s)?:
            Text(s).font(.system(size: 15)).foregroundStyle(Theme.accent).underline().lineLimit(1)
        case .text?, .number?:
            Text(MarkdownExport.display(value, property: property))
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        case nil:
            empty
        }
    }

    private var empty: some View {
        Text(emptyText).font(.system(size: 15)).foregroundStyle(Theme.faint)
    }
}

// MARK: - Board

struct BoardLayout: View {
    @Environment(AppModel.self) private var model
    let databaseID: UUID
    let schema: DatabaseSchema
    @State private var targetColumn: String?

    var body: some View {
        let columns = model.workspace.boardColumns(of: databaseID)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columns) { column in
                    // Hide the empty "No Status" column.
                    if column.option != nil || !column.rows.isEmpty {
                        columnView(column)
                    }
                }
                if let group = schema.groupProperty {
                    AddOptionButton(databaseID: databaseID, propertyID: group.id)
                }
            }
            .padding(.horizontal, 20)
        }
        .overlay {
            if schema.groupProperty == nil {
                Text("Add a Select property to group the board.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func columnView(_ column: BoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let option = column.option {
                    TagChip(option: option)
                } else {
                    Text(column.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                }
                Text("\(column.rows.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.horizontal, 4)
            ForEach(column.rows) { row in
                NavigationLink(value: row.id) {
                    BoardCard(row: row, schema: schema)
                }
                .buttonStyle(.plain)
                .draggable(row.id.uuidString) {
                    BoardCard(row: row, schema: schema).frame(width: 240)
                }
                .dropDestination(for: String.self) { items, _ in
                    drop(items, into: column, before: row.id)
                }
                .contextMenu {
                    RowMenuItems(rowID: row.id)
                    if let group = schema.groupProperty {
                        Menu("Move to") {
                            ForEach(group.options) { option in
                                Button(option.name) { model.mutate { $0.moveRow(row.id, toOption: option.id) } }
                            }
                            Button("No \(group.name)") { model.mutate { $0.moveRow(row.id, toOption: nil) } }
                        }
                    }
                }
            }
            Button {
                model.open(model.addRow(to: databaseID, option: column.option?.id))
            } label: {
                Label("New", systemImage: "plus")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 260, alignment: .top)
        .background((column.option?.color.fill ?? Theme.sunk).opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(targetColumn == column.id ? Theme.accent : .clear, lineWidth: 2))
        .dropDestination(for: String.self) { items, _ in
            drop(items, into: column, before: nil)
        } isTargeted: { over in
            if over { targetColumn = column.id } else if targetColumn == column.id { targetColumn = nil }
        }
    }

    private func drop(_ items: [String], into column: BoardColumn, before: UUID?) -> Bool {
        guard let id = items.first.flatMap(UUID.init(uuidString:)), model.page(id) != nil else { return false }
        withAnimation(.snappy) {
            model.mutate { $0.moveRow(id, toOption: column.option?.id, before: before) }
        }
        targetColumn = nil
        return true
    }
}

struct BoardCard: View {
    let row: Page
    let schema: DatabaseSchema

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if row.icon != nil { PageIcon(page: row, size: 14) }
                Text(row.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(row.title.isEmpty ? Theme.muted : Theme.ink)
                    .multilineTextAlignment(.leading)
            }
            let shown = schema.properties.filter { $0.id != schema.groupProperty?.id && row.value($0.id) != nil }
            ForEach(shown.prefix(3)) { property in
                PropertyValueView(value: row.value(property.id), property: property)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

struct AddOptionButton: View {
    @Environment(AppModel.self) private var model
    let databaseID: UUID
    let propertyID: UUID
    @State private var asking = false
    @State private var name = ""

    var body: some View {
        Button { asking = true } label: {
            Label("Add a group", systemImage: "plus")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .padding(.vertical, 10)
                .frame(width: 140)
        }
        .buttonStyle(.plain)
        .alert("New group", isPresented: $asking) {
            TextField("Name", text: $name)
            Button("Add") {
                model.addOption(name, to: propertyID, in: databaseID)
                name = ""
            }
            Button("Cancel", role: .cancel) { name = "" }
        }
    }
}

// MARK: - List

struct ListLayout: View {
    @Environment(AppModel.self) private var model
    let databaseID: UUID
    let schema: DatabaseSchema

    var body: some View {
        let rows = model.workspace.rows(of: databaseID)
        VStack(spacing: 0) {
            ForEach(rows) { row in
                NavigationLink(value: row.id) {
                    HStack(spacing: 10) {
                        PageIcon(page: row, size: 16)
                        Text(row.displayTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(row.title.isEmpty ? Theme.muted : Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        ForEach(schema.properties.filter { row.value($0.id) != nil }.prefix(2)) { property in
                            PropertyValueView(value: row.value(property.id), property: property)
                        }
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { RowMenuItems(rowID: row.id) }
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            Button {
                model.open(model.addRow(to: databaseID))
            } label: {
                Label("New", systemImage: "plus")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
