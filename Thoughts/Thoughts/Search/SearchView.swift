import SwiftUI
import ThoughtsKit

/// Finds pages by title or by anything written on them.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = Screenshots.searchQuery

    var body: some View {
        List {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                Section("Recent") {
                    ForEach(model.workspace.recents(limit: 12)) { page in
                        NavigationLink(value: page.id) { ResultRow(page: page, snippet: nil) }
                    }
                }
            } else {
                let results = model.workspace.search(trimmed)
                if results.isEmpty {
                    ContentUnavailableView.search(text: trimmed)
                        .listRowBackground(Color.clear)
                } else {
                    Section("\(results.count) \(results.count == 1 ? "page" : "pages")") {
                        ForEach(results) { result in
                            if let page = model.page(result.pageID) {
                                NavigationLink(value: page.id) { ResultRow(page: page, snippet: result.snippet) }
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search pages")
    }
}

struct ResultRow: View {
    @Environment(AppModel.self) private var model
    let page: Page
    let snippet: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PageIcon(page: page, size: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(page.displayTitle)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                let path = model.workspace.path(to: page.id).dropLast().map(\.displayTitle)
                if !path.isEmpty {
                    Text(path.joined(separator: " / "))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                if let snippet {
                    Text(snippet)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
