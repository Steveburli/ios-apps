import SwiftUI
import ThoughtsKit

/// Picks a page's emoji.
struct IconPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pageID: UUID
    @State private var typed = ""

    static let groups: [(String, [String])] = [
        ("Popular", ["📝", "📄", "📚", "💡", "🚀", "✅", "📅", "🗓️", "🏡", "💭", "🎯", "⭐️", "📌", "🔥", "❤️", "🌱"]),
        ("Work", ["💼", "📊", "📈", "🧾", "🗂️", "📎", "🖊️", "💻", "📞", "✉️", "🧠", "🛠️", "⚙️", "🔑", "🏁", "🧪"]),
        ("Life", ["🍳", "🛒", "🏃", "🧘", "✈️", "🗺️", "🎵", "🎬", "🎮", "📷", "🎨", "🧩", "🐶", "🌻", "☕️", "🎁"]),
        ("Nature", ["🌲", "🌊", "⛰️", "🌙", "☀️", "🌈", "❄️", "🍂", "🌸", "🍀", "🌵", "🐝", "🦋", "🐢", "🐳", "🪴"]),
        ("Symbols", ["❗️", "❓", "⚠️", "ℹ️", "🔔", "🔒", "♻️", "➕", "✔️", "❌", "🟢", "🟡", "🔴", "🔵", "🟣", "⚫️"]),
    ]

    static func random() -> String {
        groups[0].1.randomElement() ?? "📝"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Type any emoji", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: typed) { _, value in
                            if let emoji = value.last(where: \.isEmojiLike) {
                                choose(String(emoji))
                            }
                        }
                    ForEach(IconPicker.groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.0)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                                ForEach(group.1, id: \.self) { emoji in
                                    Button { choose(emoji) } label: {
                                        Text(emoji).font(.system(size: 30))
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Remove", role: .destructive) {
                        model.update(pageID) { $0.icon = nil }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Random") { choose(IconPicker.groups.flatMap(\.1).randomElement() ?? "📝") }
                }
            }
        }
    }

    private func choose(_ emoji: String) {
        model.update(pageID) { $0.icon = emoji }
        dismiss()
    }
}

extension Character {
    /// True for emoji, not for digits or "#" (which are emoji-capable on their own).
    var isEmojiLike: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}

/// Picks a page's cover color.
struct CoverPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pageID: UUID

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(0..<Theme.covers.count, id: \.self) { index in
                        Button {
                            model.update(pageID) { $0.cover = index }
                            dismiss()
                        } label: {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.cover(index))
                                .frame(height: 56)
                                .overlay {
                                    if model.page(pageID)?.cover == index {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cover \(index + 1)")
                    }
                }
                .padding(20)
            }
            .navigationTitle("Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Remove", role: .destructive) {
                        model.update(pageID) { $0.cover = nil }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
