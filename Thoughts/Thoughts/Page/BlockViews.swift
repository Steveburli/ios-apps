import SwiftUI
import UIKit
import ThoughtsKit

/// One block on a page.
struct BlockRow: View {
    @Environment(AppModel.self) private var model
    let block: Block
    /// The number before a numbered-list item.
    let number: Int
    let actions: BlockActions
    let editor: EditorState

    var body: some View {
        content
            .padding(.leading, CGFloat(block.indent) * 24)
            .padding(.vertical, verticalPadding)
            .id(block.id)
    }

    private var verticalPadding: CGFloat {
        switch block.kind {
        case .heading1: return 10
        case .heading2: return 7
        case .heading3: return 5
        case .callout, .code, .divider: return 6
        default: return 3
        }
    }

    @ViewBuilder private var content: some View {
        switch block.kind {
        case .divider:
            DividerBlock(block: block, actions: actions)
        case .pageLink:
            PageLinkBlock(block: block, actions: actions)
        case .callout:
            HStack(alignment: .top, spacing: 10) {
                Menu {
                    ForEach(["💡", "⚠️", "✅", "📌", "🔥", "ℹ️", "❗️", "💬", "👥", "🎯", "🗓️", "⭐️"], id: \.self) { emoji in
                        Button(emoji) { actions.setCalloutIcon(block.id, emoji) }
                    }
                } label: {
                    Text(block.icon ?? "💡")
                        .font(.system(size: 20))
                        .frame(height: BlockFont.lineHeight(for: .callout))
                }
                editable
            }
            .padding(14)
            .background(Theme.calloutBackground, in: RoundedRectangle(cornerRadius: 8))
        case .quote:
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Theme.ink)
                    .frame(width: 3)
                editable
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code:
            editable
                .padding(14)
                .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 8))
        default:
            HStack(alignment: .top, spacing: 4) {
                marker
                editable
            }
        }
    }

    @ViewBuilder private var marker: some View {
        let height = BlockFont.lineHeight(for: block.kind)
        switch block.kind {
        case .bulleted:
            Text(["•", "◦", "▪︎"][block.indent % 3])
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 24, height: height)
        case .numbered:
            Text("\(number).")
                .font(.system(size: 17).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 24, alignment: .leading)
                .frame(height: height)
        case .todo:
            Button {
                actions.toggleChecked(block.id)
            } label: {
                Image(systemName: block.checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19))
                    .foregroundStyle(block.checked ? Theme.accent : Theme.muted)
                    .frame(width: 28, height: height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(block.checked ? "Done" : "Not done")
            .sensoryFeedback(.selection, trigger: block.checked)
        case .toggle:
            Button {
                withAnimation(.snappy(duration: 0.2)) { actions.toggleCollapsed(block.id) }
            } label: {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.ink)
                    .rotationEffect(.degrees(block.collapsed ? 0 : 90))
                    .frame(width: 24, height: height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(block.collapsed ? "Show inside" : "Hide inside")
        default:
            EmptyView()
        }
    }

    private var editable: some View {
        let focused = editor.focusedBlockID == block.id
        return BlockTextView(
            text: block.text,
            kind: block.kind,
            checked: block.checked,
            cursorRequest: editor.pending?.blockID == block.id ? editor.pending?.offset : nil,
            onRequestHandled: {
                if editor.pending?.blockID == block.id { editor.pending = nil }
            },
            onChange: { actions.textChanged(block.id, $0) },
            onReturn: { actions.pressReturn(block.id, offset: $0) },
            onBackspaceAtStart: { actions.backspaceAtStart(block.id) },
            onFocusChange: { isFocused in
                if isFocused {
                    editor.focusedBlockID = block.id
                } else if editor.focusedBlockID == block.id {
                    editor.focusedBlockID = nil
                    if editor.slash?.blockID == block.id { editor.slash = nil }
                }
            }
        )
        .overlay(alignment: .topLeading) {
            if block.text.isEmpty, let hint = placeholder(focused: focused) {
                Text(hint)
                    .font(Font(BlockFont.font(for: block.kind) as CTFont))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func placeholder(focused: Bool) -> String? {
        switch block.kind {
        case .text: return focused ? "Type \"/\" for commands" : nil
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulleted, .numbered: return focused ? "List" : nil
        case .todo: return "To-do"
        case .toggle: return "Toggle"
        case .quote: return "Empty quote"
        case .callout: return "Type something…"
        case .code: return "Code"
        case .divider, .pageLink: return nil
        }
    }
}

struct DividerBlock: View {
    let block: Block
    let actions: BlockActions

    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .contextMenu {
                Button { actions.moveUp(block.id) } label: { Label("Move up", systemImage: "arrow.up") }
                Button { actions.moveDown(block.id) } label: { Label("Move down", systemImage: "arrow.down") }
                Button(role: .destructive) { actions.delete(block.id) } label: { Label("Delete", systemImage: "trash") }
            }
            .accessibilityLabel("Divider")
    }
}

struct PageLinkBlock: View {
    @Environment(AppModel.self) private var model
    let block: Block
    let actions: BlockActions

    var body: some View {
        let target = model.page(block.linkedPageID)
        let inTrash = block.linkedPageID.map { model.workspace.isInTrash($0) } ?? false
        Group {
            if let target {
                NavigationLink(value: target.id) {
                    label(target, inTrash: inTrash)
                }
                .buttonStyle(.plain)
            } else {
                label(nil, inTrash: false)
            }
        }
        .contextMenu {
            Button { actions.moveUp(block.id) } label: { Label("Move up", systemImage: "arrow.up") }
            Button { actions.moveDown(block.id) } label: { Label("Move down", systemImage: "arrow.down") }
            Button(role: .destructive) { actions.delete(block.id) } label: { Label("Remove link", systemImage: "xmark") }
        }
    }

    private func label(_ target: Page?, inTrash: Bool) -> some View {
        HStack(spacing: 8) {
            PageIcon(page: target, size: 18)
            Text(target?.displayTitle ?? "Missing page")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(target == nil || inTrash ? Theme.muted : Theme.ink)
                .underline(true, color: Theme.line)
                .strikethrough(inTrash)
                .lineLimit(1)
            if inTrash {
                Text("In Trash").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// The "/" menu, shown just above the keyboard.
struct SlashMenu: View {
    let editor: EditorState
    let actions: BlockActions

    var body: some View {
        let results = editor.slashResults
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(editor.slash?.query.isEmpty == false ? "Results" : "Basic blocks")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    editor.slash = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 26)
                }
                .accessibilityLabel("Close menu")
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.top, 6)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        Button {
                            actions.apply(command)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: command.symbol)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 38, height: 38)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(command.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Theme.ink)
                                    Text(command.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if index == 0 && editor.slash?.fromButton == false {
                                    Image(systemName: "return")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.faint)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 250)
        }
        .background(Theme.sunk)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// The bar above the keyboard: insert, turn into, indent, move and delete the focused block.
struct EditorToolbar: View {
    @Environment(AppModel.self) private var model
    let pageID: UUID
    let editor: EditorState
    let actions: BlockActions

    var body: some View {
        let id = editor.focusedBlockID
        let block = model.page(pageID)?.blocks.first { $0.id == id }
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    tool("plus", "Insert a block") { actions.openInsertMenu() }
                    Menu {
                        ForEach(BlockKind.turnIntoChoices, id: \.self) { kind in
                            Button {
                                if let id { actions.turn(id, into: kind) }
                            } label: {
                                Label(kind.displayName, systemImage: kind.symbol)
                            }
                            .disabled(block?.kind == kind)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: block?.kind.symbol ?? "textformat")
                            Text(block?.kind.displayName ?? "Text")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 40)
                    }
                    .accessibilityLabel("Turn into")
                    if block?.kind == .todo {
                        tool(block?.checked == true ? "checkmark.square.fill" : "checkmark.square", "Tick") {
                            if let id { actions.toggleChecked(id) }
                        }
                    }
                    tool("increase.indent", "Indent") { if let id { actions.indent(id) } }
                    tool("decrease.indent", "Outdent") { if let id { actions.outdent(id) } }
                    tool("arrow.up", "Move up") { if let id { actions.moveUp(id) } }
                    tool("arrow.down", "Move down") { if let id { actions.moveDown(id) } }
                    tool("plus.square.on.square", "Duplicate") { if let id { actions.duplicate(id) } }
                    tool("trash", "Delete block") { if let id { actions.delete(id) } }
                }
                .padding(.horizontal, 6)
            }
            Rectangle().fill(Theme.line).frame(width: 1, height: 24)
            tool("keyboard.chevron.compact.down", "Hide keyboard") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 44)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func tool(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
