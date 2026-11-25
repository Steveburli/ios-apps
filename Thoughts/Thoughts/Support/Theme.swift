import SwiftUI
import UIKit
import ThoughtsKit

/// Thoughts' look: warm paper and ink, with a deep teal accent. Light and dark.
enum Theme {
    static let paper = Color(light: 0xFCFBF8, dark: 0x191919)
    static let surface = Color(light: 0xFFFFFF, dark: 0x232323)
    static let sunk = Color(light: 0xF3F1EC, dark: 0x2B2B2B)
    static let ink = Color(light: 0x2B2A27, dark: 0xEDEBE6)
    static let muted = Color(light: 0x8A867E, dark: 0x9B988F)
    static let faint = Color(light: 0xB9B5AC, dark: 0x5E5C57)
    static let line = Color(light: 0xE8E5DE, dark: 0x343434)
    static let accent = Color(light: 0x0F766E, dark: 0x4FD1C5)
    static let accentSoft = Color(light: 0xE0F2EF, dark: 0x16302E)
    static let calloutBackground = Color(light: 0xF4F1EA, dark: 0x2A2926)
    static let codeBackground = Color(light: 0xF2F0EB, dark: 0x262626)

    static let uiInk = UIColor(light: 0x2B2A27, dark: 0xEDEBE6)
    static let uiMuted = UIColor(light: 0x8A867E, dark: 0x9B988F)

    /// Page covers, picked by index. Pairs of colors for a soft gradient.
    static let covers: [(Color, Color)] = [
        (Color(hex: 0x0F766E), Color(hex: 0x5EAAA8)),
        (Color(hex: 0xE9C46A), Color(hex: 0xF4A261)),
        (Color(hex: 0x264653), Color(hex: 0x2A9D8F)),
        (Color(hex: 0xA8DADC), Color(hex: 0x457B9D)),
        (Color(hex: 0xE76F51), Color(hex: 0xF4A261)),
        (Color(hex: 0x6D597A), Color(hex: 0xB56576)),
        (Color(hex: 0x84A98C), Color(hex: 0x52796F)),
        (Color(hex: 0xFFAFCC), Color(hex: 0xBDE0FE)),
        (Color(hex: 0x3D405B), Color(hex: 0x81B29A)),
        (Color(hex: 0xF2CC8F), Color(hex: 0xE07A5F)),
    ]

    static func cover(_ index: Int) -> LinearGradient {
        let pair = covers[((index % covers.count) + covers.count) % covers.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension TagColor {
    /// Text color of a tag.
    var ink: Color {
        switch self {
        case .gray: return Color(light: 0x5F5E5B, dark: 0xC4C2BD)
        case .brown: return Color(light: 0x7A5434, dark: 0xD9B99B)
        case .orange: return Color(light: 0xA34F0C, dark: 0xF2B27A)
        case .yellow: return Color(light: 0x8A6310, dark: 0xF0D27A)
        case .green: return Color(light: 0x2D6B47, dark: 0x8FD3A8)
        case .blue: return Color(light: 0x245E8F, dark: 0x8EC2F0)
        case .purple: return Color(light: 0x6B3F96, dark: 0xC8A6EE)
        case .pink: return Color(light: 0x9A3268, dark: 0xF0A2C8)
        case .red: return Color(light: 0xA8322B, dark: 0xF59A92)
        }
    }

    /// Background of a tag.
    var fill: Color {
        switch self {
        case .gray: return Color(light: 0xEBEAE7, dark: 0x3A3936)
        case .brown: return Color(light: 0xF1E6DC, dark: 0x45362A)
        case .orange: return Color(light: 0xFBE6D3, dark: 0x4D3221)
        case .yellow: return Color(light: 0xF8EDC8, dark: 0x4A3F1E)
        case .green: return Color(light: 0xDCEFE2, dark: 0x203B2B)
        case .blue: return Color(light: 0xDCEAF6, dark: 0x1F3448)
        case .purple: return Color(light: 0xEBE1F5, dark: 0x352947)
        case .pink: return Color(light: 0xF7DFEB, dark: 0x45263A)
        case .red: return Color(light: 0xF9DEDB, dark: 0x4A2622)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}

/// A page's emoji, or a plain symbol when it has none.
struct PageIcon: View {
    let page: Page?
    var size: CGFloat = 18

    var body: some View {
        if let icon = page?.icon, !icon.isEmpty {
            Text(icon)
                .font(.system(size: size))
                .frame(width: size * 1.3, height: size * 1.3)
        } else {
            Image(systemName: page?.kind == .database ? "tablecells" : "doc.text")
                .font(.system(size: size * 0.85, weight: .regular))
                .foregroundStyle(Theme.muted)
                .frame(width: size * 1.3, height: size * 1.3)
        }
    }
}

/// A colored option chip, like a status.
struct TagChip: View {
    let option: SelectOption

    var body: some View {
        Text(option.name)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(option.color.ink)
            .background(option.color.fill, in: RoundedRectangle(cornerRadius: 5))
    }
}

extension Date {
    /// "Edited 5m ago" style.
    var relativeText: String {
        let seconds = Date().timeIntervalSince(self)
        if seconds < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}
