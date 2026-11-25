import Foundation

/// Ready-made pages to start from.
public struct PageTemplate: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var icon: String
    public var summary: String
}

private func b(_ kind: BlockKind, _ text: String = "", indent: Int = 0, checked: Bool = false,
               collapsed: Bool = false, icon: String? = nil) -> Block {
    Block(kind: kind, text: text, indent: indent, checked: checked, collapsed: collapsed, icon: icon)
}

public enum Templates {
    public static let all: [PageTemplate] = [
        PageTemplate(id: "meeting", title: "Meeting notes", icon: "🗓️", summary: "Agenda, notes and action items."),
        PageTemplate(id: "todo", title: "To-do list", icon: "✅", summary: "A simple checklist."),
        PageTemplate(id: "journal", title: "Journal entry", icon: "📓", summary: "Gratitude, reflection, tomorrow."),
        PageTemplate(id: "weekly", title: "Weekly plan", icon: "📅", summary: "A heading and to-dos for each day."),
        PageTemplate(id: "projects", title: "Projects", icon: "🚀", summary: "A board of projects by status."),
        PageTemplate(id: "reading", title: "Reading list", icon: "📚", summary: "Books with author, status and rating."),
    ]

    /// Adds the template as a new page and returns its ID.
    @discardableResult
    public static func add(_ templateID: String, to workspace: inout Workspace, parentID: UUID? = nil,
                           now: Date = Date()) -> UUID? {
        guard let template = all.first(where: { $0.id == templateID }) else { return nil }
        switch templateID {
        case "meeting":
            return workspace.createPage(title: template.title, icon: template.icon, parentID: parentID, blocks: [
                b(.callout, "Date, time and who's coming.", icon: "👥"),
                b(.heading2, "Agenda"),
                b(.numbered, ""),
                b(.heading2, "Notes"),
                b(.text, ""),
                b(.heading2, "Action items"),
                b(.todo, ""),
            ], now: now)
        case "todo":
            return workspace.createPage(title: template.title, icon: template.icon, parentID: parentID, blocks: [
                b(.todo, ""),
                b(.todo, ""),
                b(.todo, ""),
            ], now: now)
        case "journal":
            return workspace.createPage(title: template.title, icon: template.icon, parentID: parentID, blocks: [
                b(.heading3, "Three things I'm grateful for"),
                b(.numbered, ""),
                b(.numbered, ""),
                b(.numbered, ""),
                b(.heading3, "What happened today"),
                b(.text, ""),
                b(.heading3, "Tomorrow"),
                b(.todo, ""),
            ], now: now)
        case "weekly":
            var blocks: [Block] = []
            for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] {
                blocks.append(b(.heading3, day))
                blocks.append(b(.todo, ""))
            }
            return workspace.createPage(title: template.title, icon: template.icon, parentID: parentID,
                                        blocks: blocks, now: now)
        case "projects":
            return projects(in: &workspace, parentID: parentID, rows: [], now: now)
        case "reading":
            return reading(in: &workspace, parentID: parentID, rows: [], now: now)
        default:
            return nil
        }
    }

    /// A board of projects with Status, Priority and Due. Rows are (title, status 0–2, priority 0–2, days until due).
    @discardableResult
    static func projects(in workspace: inout Workspace, parentID: UUID?, rows: [(String, Int, Int, Int?)],
                         now: Date) -> UUID {
        let status = PropertyDefinition(name: "Status", type: .select, options: [
            SelectOption(name: "Not started", color: .gray),
            SelectOption(name: "In progress", color: .blue),
            SelectOption(name: "Done", color: .green),
        ])
        let priority = PropertyDefinition(name: "Priority", type: .select, options: [
            SelectOption(name: "Low", color: .yellow),
            SelectOption(name: "Medium", color: .orange),
            SelectOption(name: "High", color: .red),
        ])
        let due = PropertyDefinition(name: "Due", type: .date)
        let id = workspace.createPage(title: "Projects", icon: "🚀", parentID: parentID, kind: .database, now: now)
        workspace[id]?.database = DatabaseSchema(properties: [status, priority, due], layout: .board, groupByID: status.id)
        for row in rows {
            var values: [UUID: PropertyValue] = [
                status.id: .select(status.options[row.1].id),
                priority.id: .select(priority.options[row.2].id),
            ]
            if let days = row.3 { values[due.id] = .date(now.addingTimeInterval(Double(days) * 86_400)) }
            workspace.addRow(to: id, title: row.0, values: values, now: now)
        }
        return id
    }

    /// A table of books. Rows are (title, author, status 0–2, stars 0–5).
    @discardableResult
    static func reading(in workspace: inout Workspace, parentID: UUID?, rows: [(String, String, Int, Int)],
                        now: Date) -> UUID {
        let status = PropertyDefinition(name: "Status", type: .select, options: [
            SelectOption(name: "Want to read", color: .gray),
            SelectOption(name: "Reading", color: .blue),
            SelectOption(name: "Finished", color: .green),
        ])
        let author = PropertyDefinition(name: "Author", type: .text)
        let rating = PropertyDefinition(name: "Rating", type: .select, options: (1...5).map {
            SelectOption(name: String(repeating: "★", count: $0), color: .yellow)
        })
        let id = workspace.createPage(title: "Reading list", icon: "📚", parentID: parentID, kind: .database, now: now)
        workspace[id]?.database = DatabaseSchema(properties: [author, status, rating], layout: .table, groupByID: status.id)
        for row in rows {
            var values: [UUID: PropertyValue] = [
                author.id: .text(row.1),
                status.id: .select(status.options[row.2].id),
            ]
            if row.3 > 0 { values[rating.id] = .select(rating.options[row.3 - 1].id) }
            workspace.addRow(to: id, title: row.0, values: values, now: now)
        }
        return id
    }
}

extension Workspace {
    /// What a new install opens with: a guide to the app and a few example pages.
    public static func sample(now: Date = Date()) -> Workspace {
        var w = Workspace()
        let start = now.addingTimeInterval(-3 * 86_400)

        let guide = w.createPage(title: "Getting started", icon: "👋", blocks: [
            b(.callout, "Welcome to Thoughts. Everything here is a block you can edit, move and change.", icon: "💡"),
            b(.heading2, "The basics"),
            b(.todo, "Tap anywhere and start typing", checked: true),
            b(.todo, "Type / for the block menu: headings, lists, to-dos, toggles and more"),
            b(.todo, "Press return on an empty list item to end the list"),
            b(.todo, "Use the bar above the keyboard to indent, move or turn a block into something else"),
            b(.todo, "Touch and hold a page on Home to favorite, move or duplicate it"),
            b(.heading2, "Shortcuts as you type"),
            b(.toggle, "Show the shortcuts"),
            b(.bulleted, "# then space for a big heading (## and ### for smaller)", indent: 1),
            b(.bulleted, "- or * then space for a bullet", indent: 1),
            b(.bulleted, "1. then space for a numbered list", indent: 1),
            b(.bulleted, "[] then space for a to-do", indent: 1),
            b(.bulleted, "> then space for a toggle, \" then space for a quote", indent: 1),
            b(.bulleted, "--- for a divider, ``` for code", indent: 1),
            b(.divider),
            b(.quote, "Write it down. Then you're free to think about something else."),
        ], now: start)
        w[guide]?.cover = 0

        let home = w.createPage(title: "Personal home", icon: "🏡", blocks: [
            b(.text, "My corner for plans, books and ideas."),
            b(.heading3, "This week"),
            b(.todo, "Book the dentist", checked: true),
            b(.todo, "Call Mom on Sunday"),
            b(.todo, "Fix the squeaky gate"),
        ], now: start.addingTimeInterval(60))
        w[home]?.cover = 3

        let reading = Templates.reading(in: &w, parentID: home, rows: [
            ("The Overstory", "Richard Powers", 2, 5),
            ("Project Hail Mary", "Andy Weir", 1, 0),
            ("Four Thousand Weeks", "Oliver Burkeman", 2, 4),
            ("Braiding Sweetgrass", "Robin Wall Kimmerer", 0, 0),
        ], now: start.addingTimeInterval(120))
        let ideas = w.createPage(title: "Ideas", icon: "💭", parentID: home, blocks: [
            b(.bulleted, "Herb garden on the back step"),
            b(.bulleted, "A family recipe book"),
            b(.bulleted, "Weekend trip to the coast", indent: 0),
            b(.bulleted, "Look at cabins near the lighthouse", indent: 1),
        ], now: start.addingTimeInterval(180))
        w[home]?.blocks.append(Block(kind: .heading3, text: "Pages"))
        w[home]?.blocks.append(Block(kind: .pageLink, linkedPageID: reading))
        w[home]?.blocks.append(Block(kind: .pageLink, linkedPageID: ideas))

        let projects = Templates.projects(in: &w, parentID: nil, rows: [
            ("Kitchen repaint", 1, 1, 6),
            ("Plan summer trip", 0, 2, 21),
            ("Sort the garage", 0, 0, nil),
            ("New bike tires", 2, 1, -2),
            ("Photo album for Dad", 1, 2, 3),
        ], now: start.addingTimeInterval(240))

        let meeting = Templates.add("meeting", to: &w, now: start.addingTimeInterval(300))!
        w[meeting]?.title = "Team check-in"
        w[meeting]?.blocks = [
            b(.callout, "Tuesday 10:00 · Sam, Priya, Lee", icon: "👥"),
            b(.heading2, "Agenda"),
            b(.numbered, "Launch timeline"),
            b(.numbered, "Customer feedback"),
            b(.numbered, "Holiday coverage"),
            b(.heading2, "Notes"),
            b(.text, "Launch moves a week to fit the extra testing. Feedback is mostly about search."),
            b(.heading2, "Action items"),
            b(.todo, "Send the new timeline", checked: true),
            b(.todo, "Group feedback by theme"),
            b(.todo, "Share the holiday rota"),
        ]

        w.toggleFavorite(guide, now: start)
        w.toggleFavorite(projects, now: start.addingTimeInterval(1))
        w.markOpened(projects, now: now.addingTimeInterval(-600))
        w.markOpened(meeting, now: now.addingTimeInterval(-3_600))
        w.markOpened(reading, now: now.addingTimeInterval(-7_200))
        w.markOpened(guide, now: now.addingTimeInterval(-86_400))
        w.markOpened(home, now: now.addingTimeInterval(-90_000))
        return w
    }
}
