import Foundation

/// Turns a page into Markdown for sharing or copying.
public enum MarkdownExport {
    public static func markdown(for pageID: UUID, in workspace: Workspace, dateFormat: (Date) -> String = MarkdownExport.defaultDate) -> String {
        guard let page = workspace[pageID] else { return "" }
        var lines: [String] = []
        let icon = page.icon.map { $0 + " " } ?? ""
        lines.append("# \(icon)\(page.displayTitle)")
        lines.append("")

        if let db = workspace.database(of: pageID)?.database {
            for property in db.properties {
                let text = display(page.value(property.id), property: property, dateFormat: dateFormat)
                if !text.isEmpty { lines.append("**\(property.name):** \(text)  ") }
            }
            if !db.properties.isEmpty { lines.append("") }
        }

        if page.kind == .database, let schema = page.database {
            let rows = workspace.rows(of: pageID)
            let header = ["Name"] + schema.properties.map(\.name)
            lines.append("| " + header.map(cell).joined(separator: " | ") + " |")
            lines.append("|" + header.map { _ in " --- " }.joined(separator: "|") + "|")
            for row in rows {
                let values = [row.displayTitle] + schema.properties.map { display(row.value($0.id), property: $0, dateFormat: dateFormat) }
                lines.append("| " + values.map(cell).joined(separator: " | ") + " |")
            }
            lines.append("")
        }

        var inCode = false
        for (index, block) in page.blocks.enumerated() {
            let pad = String(repeating: "  ", count: block.indent)
            if inCode && block.kind != .code { inCode = false }
            switch block.kind {
            case .text: lines.append(block.text.isEmpty ? "" : pad + block.text)
            case .heading1: lines.append("## " + block.text)
            case .heading2: lines.append("### " + block.text)
            case .heading3: lines.append("#### " + block.text)
            case .bulleted, .toggle: lines.append(pad + "- " + block.text)
            case .numbered: lines.append(pad + "\(BlockEditing.number(page.blocks, at: index)). " + block.text)
            case .todo: lines.append(pad + (block.checked ? "- [x] " : "- [ ] ") + block.text)
            case .quote: lines.append(pad + "> " + block.text)
            case .callout: lines.append(pad + "> " + (block.icon.map { $0 + " " } ?? "") + block.text)
            case .divider: lines.append("---")
            case .code:
                lines.append("```")
                lines.append(block.text)
                lines.append("```")
            case .pageLink:
                let title = block.linkedPageID.flatMap { workspace[$0] }?.displayTitle ?? "Missing page"
                lines.append(pad + "📄 " + title)
            }
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    static func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    public static func defaultDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// A value as plain text: option names, "Yes" for a ticked box, and so on.
    public static func display(_ value: PropertyValue?, property: PropertyDefinition,
                               dateFormat: (Date) -> String = MarkdownExport.defaultDate) -> String {
        guard let value else { return "" }
        switch value {
        case .text(let s), .url(let s): return s
        case .number(let n): return Workspace.format(number: n)
        case .select(let id): return property.option(id)?.name ?? ""
        case .multiSelect(let ids): return ids.compactMap { property.option($0)?.name }.joined(separator: ", ")
        case .date(let d): return dateFormat(d)
        case .checkbox(let on): return on ? "Yes" : "No"
        }
    }
}
