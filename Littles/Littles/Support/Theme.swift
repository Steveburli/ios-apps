import SwiftUI
import UIKit
import LittlesKit

/// Littles' palette, light and dark: warm paper, teal accent, one color per kid.
enum Theme {
    static let bg = Color(light: 0xFBF7F0, dark: 0x14120F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1F1C18)
    static let sunk = Color(light: 0xF3ECE1, dark: 0x2A2621)
    static let ink = Color(light: 0x2B2420, dark: 0xF3EDE6)
    static let muted = Color(light: 0x786C62, dark: 0xA99E93)
    static let line = Color(light: 0xEADFD1, dark: 0x37312A)
    static let accent = Color(light: 0x0E7C70, dark: 0x4FD1C0)
    static let accentSoft = Color(light: 0xD8F1EC, dark: 0x163A35)
    static let warn = Color(light: 0xC2410C, dark: 0xFF8A4C)
    static let warnSoft = Color(light: 0xFFE9DB, dark: 0x3B2114)
    static let good = Color(light: 0x15803D, dark: 0x4ADE80)

    static let radius: CGFloat = 20

    /// Kid colors, picked per kid in Family.
    static let kidHex: [UInt32] = [0xE0742B, 0x3B7DD8, 0x8E5BD6, 0x2E9E66, 0xD6457A, 0xB8901A]
    static let kidColors: [Color] = kidHex.map { Color(hex: $0) }

    static func color(_ kid: Kid?) -> Color {
        guard let kid else { return accent }
        return kidColors[((kid.color % kidColors.count) + kidColors.count) % kidColors.count]
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

/// A rounded surface card.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

extension View {
    func card() -> some View {
        modifier(CardBackground())
    }
}

/// A small heading above a group of cards.
struct SectionTitle: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(text)
                .font(Theme.display(20))
                .foregroundStyle(Theme.ink)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 8)
    }
}

/// A colored capsule label.
struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : color)
            .background(filled ? color : color.opacity(0.14), in: Capsule())
    }
}

/// The kid's initial or emoji in their color.
struct KidBadge: View {
    let kid: Kid
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(Theme.color(kid))
            Text(kid.emoji.isEmpty ? kid.initial : kid.emoji)
                .font(.system(size: size * (kid.emoji.isEmpty ? 0.5 : 0.55), weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// The row of kid chips at the top of a tab. `allowBoth` adds a "Both" chip
/// (selection "") for screens that can show everyone.
struct KidPicker: View {
    @EnvironmentObject var model: AppModel
    @Binding var selection: String
    var allowBoth = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if allowBoth {
                    chip(title: "Everyone", subtitle: nil, color: Theme.accent, badge: nil, selected: selection.isEmpty) {
                        selection = ""
                    }
                }
                ForEach(model.state.kids) { kid in
                    chip(title: kid.name, subtitle: kid.ageLabel(on: Date()), color: Theme.color(kid), badge: kid,
                         selected: selection == kid.id) {
                        selection = kid.id
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(title: String, subtitle: String?, color: Color, badge: Kid?, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let badge { KidBadge(kid: badge, size: 28) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.subheadline.weight(.bold))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption2.weight(.semibold)).opacity(0.8)
                    }
                }
            }
            .padding(.leading, badge == nil ? 14 : 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Theme.ink)
            .background(selected ? color : Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(selected ? color : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A big friendly empty-state message.
struct EmptyNote: View {
    let emoji: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Text(emoji).font(.system(size: 40))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

/// Weekday toggles, Sunday first (1...7).
struct WeekdayPicker: View {
    @Binding var days: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.removeAll { $0 == day } } else { days.append(day); days.sort() }
                } label: {
                    Text(Dates.letterWeekdays[day - 1])
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(on ? Color.white : Theme.ink)
                        .background(on ? Theme.accent : Theme.sunk, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Dates.shortWeekdays[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Picks which kids something is for. Empty means everyone.
struct KidsToggle: View {
    @EnvironmentObject var model: AppModel
    @Binding var kidIDs: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.state.kids) { kid in
                let on = kidIDs.isEmpty || kidIDs.contains(kid.id)
                Button {
                    var set = kidIDs.isEmpty ? model.state.kids.map { $0.id } : kidIDs
                    if on { set.removeAll { $0 == kid.id } } else { set.append(kid.id) }
                    // Everyone selected, or nobody, both mean "everyone".
                    kidIDs = (set.count == model.state.kids.count || set.isEmpty) ? [] : set
                } label: {
                    HStack(spacing: 6) {
                        KidBadge(kid: kid, size: 22)
                        Text(kid.name).font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(on ? Color.white : Theme.ink)
                    .background(on ? Theme.color(kid) : Theme.sunk, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minutes after midnight, edited with a time picker.
struct MinutesPicker: View {
    let title: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { Dates.at(Dates.key(Date()), minutes: minutes) ?? Date() },
            set: { minutes = Dates.minutes($0) }
        ), displayedComponents: .hourAndMinute)
    }
}
