import Foundation
import ThoughtsKit

/// The cloud build launches the app with `-screenshots <screen>` to photograph each screen
/// with the example pages: home, page, slash, table, board, row, search or settings.
/// Nothing here runs in normal use, and nothing is saved.
enum Screenshots {
    static let screen: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }()

    static var isActive: Bool {
        screen != nil
    }

    /// What the search screen starts with.
    static var searchQuery: String {
        screen == "search" ? "launch" : ""
    }

    static func makeModel() -> AppModel {
        let model = AppModel(workspace: Workspace.sample(), savesToDisk: false)
        model.appearance = .system
        return model
    }

    private static func pageID(_ title: String, in model: AppModel) -> UUID? {
        model.workspace.pages.values.first { $0.title == title }?.id
    }

    /// Opens the screen to photograph.
    static func prepare(_ model: AppModel) {
        guard let screen else { return }
        if let home = pageID("Personal home", in: model) { model.expanded.insert(home) }
        switch screen {
        case "page":
            model.homePath = [pageID("Getting started", in: model)].compactMap { $0 }
        case "slash":
            model.homePath = [pageID("Team check-in", in: model)].compactMap { $0 }
        case "table":
            model.homePath = [pageID("Reading list", in: model)].compactMap { $0 }
        case "board":
            model.homePath = [pageID("Projects", in: model)].compactMap { $0 }
        case "row":
            if let projects = pageID("Projects", in: model),
               let row = model.workspace.children(of: projects).first(where: { $0.title == "Kitchen repaint" }) {
                model.update(row.id, touch: false) { page in
                    page.icon = "🎨"
                    page.blocks = [
                        Block(kind: .heading3, text: "Rooms"),
                        Block(kind: .todo, text: "Pick the color for the walls", checked: true),
                        Block(kind: .todo, text: "Buy rollers and tape", checked: true),
                        Block(kind: .todo, text: "Move the shelves out"),
                        Block(kind: .todo, text: "Two coats on the north wall"),
                        Block(kind: .callout, text: "Dries in about four hours between coats.", icon: "⏱️"),
                    ]
                }
                model.homePath = [projects, row.id]
            }
        case "search":
            model.tab = .search
        case "settings":
            model.tab = .settings
        default:
            break
        }
    }

    /// For the "slash" screen: shows the "/" menu and the bar above the keyboard on the meeting page.
    static func prepareEditor(_ editor: EditorState, page: Page) {
        guard screen == "slash", page.title == "Team check-in",
              let block = page.blocks.last(where: { $0.kind == .todo }) else { return }
        editor.focusedBlockID = block.id
        editor.slash = SlashState(blockID: block.id, query: "", fromButton: true)
    }
}
