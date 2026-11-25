import SwiftUI
import Observation
import ThoughtsKit

enum AppTab: Hashable {
    case home, search, settings
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Owns the workspace and saves it as `workspace.json` in Application Support,
/// a moment after each change.
@Observable
final class AppModel {
    var workspace: Workspace
    var tab: AppTab = .home
    var homePath: [UUID] = []
    var searchPath: [UUID] = []
    var settingsPath: [UUID] = []
    /// Pages open in the Home tree.
    var expanded: Set<UUID> {
        didSet { saveExpanded() }
    }
    var appearance: Appearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let savesToDisk: Bool

    static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("workspace.json")
    }

    init(workspace: Workspace? = nil, savesToDisk: Bool = true) {
        self.savesToDisk = savesToDisk
        appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        let ids = UserDefaults.standard.stringArray(forKey: "expanded.v1") ?? []
        expanded = Set(ids.compactMap(UUID.init(uuidString:)))
        if let workspace {
            self.workspace = workspace
        } else if let data = try? Data(contentsOf: AppModel.fileURL),
                  let loaded = try? JSONDecoder().decode(Workspace.self, from: data) {
            self.workspace = loaded
        } else {
            // First launch: a guide and a few example pages.
            self.workspace = Workspace.sample()
            if savesToDisk { saveNow() }
        }
    }

    private func saveExpanded() {
        UserDefaults.standard.set(expanded.map(\.uuidString), forKey: "expanded.v1")
    }

    // MARK: - Saving

    private func changed() {
        guard savesToDisk else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard savesToDisk else { return }
        saveTask?.cancel()
        do {
            let folder = AppModel.fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(workspace)
            try data.write(to: AppModel.fileURL, options: .atomic)
        } catch {
            print("Saving failed: \(error)")
        }
    }

    // MARK: - Reading

    func page(_ id: UUID?) -> Page? {
        guard let id else { return nil }
        return workspace[id]
    }

    // MARK: - Changing pages

    /// Changes a page and marks it edited.
    func update(_ id: UUID, touch: Bool = true, _ body: (inout Page) -> Void) {
        guard var page = workspace[id] else { return }
        body(&page)
        if touch { page.edited = Date() }
        workspace[id] = page
        changed()
    }

    func updateBlocks(_ pageID: UUID, _ body: (inout [Block]) -> Void) {
        update(pageID) { body(&$0.blocks) }
    }

    func mutate(_ body: (inout Workspace) -> Void) {
        body(&workspace)
        changed()
    }

    @discardableResult
    func newPage(in parentID: UUID? = nil, kind: PageKind = .document, title: String = "") -> UUID {
        var id = UUID()
        mutate { id = $0.createSubpage(in: parentID, title: title, kind: kind) }
        if let parentID { expanded.insert(parentID) }
        return id
    }

    @discardableResult
    func addTemplate(_ templateID: String, in parentID: UUID? = nil) -> UUID? {
        var id: UUID?
        mutate { w in
            id = Templates.add(templateID, to: &w, parentID: parentID)
            if let id, let parentID, w[parentID]?.kind == .document {
                w[parentID]?.blocks.append(Block(kind: .pageLink, linkedPageID: id))
            }
        }
        return id
    }

    /// Fills an empty page from a document template, keeping its title if it has one.
    func apply(template templateID: String, to pageID: UUID) {
        var scratch = Workspace()
        guard let made = Templates.add(templateID, to: &scratch), let source = scratch[made] else { return }
        if source.kind == .database {
            update(pageID) { page in
                page.kind = .database
                page.database = source.database
                if page.title.isEmpty { page.title = source.title }
                if page.icon == nil { page.icon = source.icon }
            }
            return
        }
        update(pageID) { page in
            page.blocks = source.blocks
            if page.title.trimmingCharacters(in: .whitespaces).isEmpty { page.title = source.title }
            if page.icon == nil { page.icon = source.icon }
        }
    }

    func markOpened(_ id: UUID) {
        guard workspace[id] != nil else { return }
        workspace.markOpened(id)
        changed()
    }

    func toggleFavorite(_ id: UUID) { mutate { $0.toggleFavorite(id) } }
    func trash(_ id: UUID) { mutate { $0.trash(id) } }
    func restore(_ id: UUID) { mutate { $0.restore(id) } }
    func deleteForever(_ id: UUID) { mutate { $0.deleteForever(id) } }
    func emptyTrash() { mutate { $0.emptyTrash() } }

    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        var copy: UUID?
        mutate { copy = $0.duplicate(id) }
        return copy
    }

    func move(_ id: UUID, to parent: UUID?) {
        mutate { $0.move(id, to: parent) }
        if let parent { expanded.insert(parent) }
    }

    /// Adds the guide and example pages again, next to what's already there.
    func addExamplePages() {
        let sample = Workspace.sample()
        mutate { w in
            let base = (w.roots.map(\.order).max() ?? 0)
            for var page in sample.pages.values {
                if page.parentID == nil { page.order += base }
                page.favorited = nil
                w[page.id] = page
            }
        }
    }

    // MARK: - Databases

    func setValue(_ value: PropertyValue?, row: UUID, property: UUID) {
        update(row) { $0.setValue(value, for: property) }
    }

    func updateSchema(_ databaseID: UUID, _ body: (inout DatabaseSchema) -> Void) {
        update(databaseID) { page in
            var schema = page.database ?? DatabaseSchema.starter()
            body(&schema)
            page.database = schema
        }
    }

    func updateProperty(_ databaseID: UUID, _ propertyID: UUID, _ body: (inout PropertyDefinition) -> Void) {
        updateSchema(databaseID) { schema in
            guard let i = schema.properties.firstIndex(where: { $0.id == propertyID }) else { return }
            body(&schema.properties[i])
        }
    }

    /// Adds an option to a select property and returns it.
    @discardableResult
    func addOption(_ name: String, to propertyID: UUID, in databaseID: UUID) -> SelectOption? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let count = page(databaseID)?.database?.property(propertyID)?.options.count ?? 0
        let option = SelectOption(name: trimmed, color: TagColor.allCases[(count + 1) % TagColor.allCases.count])
        updateProperty(databaseID, propertyID) { $0.options.append(option) }
        return option
    }

    @discardableResult
    func addRow(to databaseID: UUID, option: UUID? = nil) -> UUID {
        var id = UUID()
        mutate { w in
            var values: [UUID: PropertyValue] = [:]
            if let option, let group = w[databaseID]?.database?.groupProperty {
                values[group.id] = .select(option)
            }
            id = w.addRow(to: databaseID, values: values)
        }
        return id
    }

    // MARK: - Navigation

    /// Opens a page on the current tab's stack.
    func open(_ id: UUID) {
        switch tab {
        case .home: homePath.append(id)
        case .search: searchPath.append(id)
        case .settings: settingsPath.append(id)
        }
    }
}
