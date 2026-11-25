import SwiftUI
import ThoughtsKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingExamples = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $model.appearance) {
                    ForEach(Appearance.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                NavigationLink {
                    TrashView()
                } label: {
                    HStack {
                        Label("Trash", systemImage: "trash")
                        Spacer()
                        let count = model.workspace.trashed.count
                        if count > 0 { Text("\(count)").foregroundStyle(Theme.muted) }
                    }
                }
                ShareLink(item: allMarkdown, subject: Text("Thoughts export")) {
                    Label("Export everything as Markdown", systemImage: "square.and.arrow.up")
                }
                Button {
                    confirmingExamples = true
                } label: {
                    Label("Add the example pages", systemImage: "sparkles")
                }
            }
            Section {
                LabeledContent("Pages", value: "\(model.workspace.pages.values.filter { !model.workspace.isInTrash($0.id) }.count)")
                LabeledContent("Words", value: "\(model.workspace.pages.values.reduce(0) { $0 + $1.wordCount })")
            } header: {
                Text("Your workspace")
            } footer: {
                Text("Everything stays on this iPhone. Nothing is sent anywhere.")
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle("Settings")
        .confirmationDialog("Add the guide and example pages?", isPresented: $confirmingExamples, titleVisibility: .visible) {
            Button("Add them") { model.addExamplePages() }
        } message: {
            Text("Your own pages stay as they are.")
        }
    }

    private var allMarkdown: String {
        model.workspace.roots
            .flatMap { [$0.id] + model.workspace.descendants(of: $0.id) }
            .filter { !model.workspace.isInTrash($0) && !model.workspace.isRow($0) }
            .map { MarkdownExport.markdown(for: $0, in: model.workspace) }
            .joined(separator: "\n\n---\n\n")
    }
}

/// Pages in the Trash: restore them or delete them for good.
struct TrashView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingEmpty = false

    var body: some View {
        List {
            let trashed = model.workspace.trashed
            if trashed.isEmpty {
                ContentUnavailableView("Trash is empty", systemImage: "trash",
                                       description: Text("Pages you delete wait here until you empty it."))
                    .listRowBackground(Color.clear)
            }
            ForEach(trashed) { page in
                HStack(spacing: 10) {
                    PageIcon(page: page, size: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(page.displayTitle).foregroundStyle(Theme.ink)
                        if let date = page.trashed {
                            Text("Deleted \(date.relativeText)").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    Button("Restore") { model.restore(page.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { model.deleteForever(page.id) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Trash")
        .toolbar {
            if !model.workspace.trashed.isEmpty {
                Button("Empty", role: .destructive) { confirmingEmpty = true }
            }
        }
        .confirmationDialog("Delete everything in the Trash for good?", isPresented: $confirmingEmpty,
                            titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        }
    }
}
