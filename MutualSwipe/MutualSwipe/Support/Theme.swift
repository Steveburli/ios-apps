import SwiftUI
import UIKit
import MutualKit

/// The artifact's palette, light and dark.
enum Theme {
    static let bg = Color(light: 0xF1F2F7, dark: 0x0D0E15)
    static let surface = Color(light: 0xFFFFFF, dark: 0x171925)
    static let sunk = Color(light: 0xE6E8F0, dark: 0x202331)
    static let ink = Color(light: 0x161726, dark: 0xECEEF6)
    static let muted = Color(light: 0x5B6075, dark: 0x9A9FB5)
    static let line = Color(light: 0xD9DCE6, dark: 0x2A2D3C)
    static let accent = Color(light: 0xD01C5B, dark: 0xFF5A8E)
    static let accentInk = Color(light: 0xFFFFFF, dark: 0x22040F)
    static let accentSoft = Color(light: 0xFBE1EA, dark: 0x3B1224)

    /// Card and player colors.
    static let palette: [Color] = [0xC2410C, 0x0F766E, 0x1D4ED8, 0x9D174D, 0x6D28D9, 0x166534, 0xA16207, 0x334155]
        .map { Color(light: $0, dark: $0) }

    static func cardColor(_ cardID: String) -> Color {
        palette[CardText.colorIndex(cardID)]
    }

    static func playerColor(_ player: Player?) -> Color {
        guard let player else { return palette[7] }
        return palette[max(0, min(7, player.color))]
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

/// How each vote looks: its color, soft background, symbol and stamp color.
extension Vote {
    var color: Color {
        switch self {
        case .love: return Color(light: 0xB97A00, dark: 0xFFC23D)
        case .like: return Color(light: 0x0E8C52, dark: 0x3DD68C)
        case .nope: return Color(light: 0x5F6680, dark: 0xA6ACC2)
        case .never: return Color(light: 0xCC2A1E, dark: 0xFF6F61)
        }
    }

    var soft: Color {
        switch self {
        case .love: return Color(light: 0xFFF1CF, dark: 0x392B08)
        case .like: return Color(light: 0xD9F3E5, dark: 0x0D3021)
        case .nope: return Color(light: 0xE9EBF2, dark: 0x252837)
        case .never: return Color(light: 0xFCE1DE, dark: 0x3B1512)
        }
    }

    var stampColor: Color {
        switch self {
        case .love: return Color(hex: 0xA86C00)
        case .like: return Color(hex: 0x0B7A47)
        case .nope: return Color(hex: 0x3F4559)
        case .never: return Color(hex: 0xB71C1C)
        }
    }

    var symbol: String {
        switch self {
        case .love: return "star.fill"
        case .like: return "heart.fill"
        case .nope: return "xmark"
        case .never: return "nosign"
        }
    }

    /// The swipe direction, for VoiceOver and the hint line.
    var direction: String {
        switch self {
        case .love: return "Swipe up"
        case .like: return "Swipe right"
        case .nope: return "Swipe left"
        case .never: return "Swipe down"
        }
    }
}

extension Verdict {
    var color: Color {
        switch self {
        case .perfect: return Vote.love.color
        case .match: return Vote.like.color
        case .debate: return Theme.accent
        case .split, .pending: return Vote.nope.color
        case .trash: return Vote.never.color
        }
    }

    var soft: Color {
        switch self {
        case .perfect: return Vote.love.soft
        case .match: return Vote.like.soft
        case .debate: return Theme.accentSoft
        case .split, .pending: return Vote.nope.soft
        case .trash: return Vote.never.soft
        }
    }

    var symbol: String {
        switch self {
        case .perfect: return Vote.love.symbol
        case .match: return Vote.like.symbol
        case .debate: return "bubble.left.fill"
        case .split, .pending: return Vote.nope.symbol
        case .trash: return Vote.never.symbol
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Shared pieces

/// Two overlapping rings with the overlap filled: the Mutual mark.
struct BrandMark: View {
    var body: some View {
        Canvas { context, size in
            let r = size.height / 2 - 1
            let left = CGRect(x: size.width / 2 - r * 1.33 - 0, y: 1, width: r * 2, height: r * 2)
            let right = left.offsetBy(dx: r * 0.66 + 1.4, dy: 0)
            var lens = Path(ellipseIn: left)
            lens = lens.intersection(Path(ellipseIn: right))
            context.fill(lens, with: .color(Theme.accent))
            context.stroke(Path(ellipseIn: left), with: .color(Theme.ink), lineWidth: 2)
            context.stroke(Path(ellipseIn: right), with: .color(Theme.ink), lineWidth: 2)
        }
        .frame(width: 30, height: 20)
        .accessibilityHidden(true)
    }
}

/// A player's initial in their color.
struct PlayerDot: View {
    let player: Player?
    var size: CGFloat = 26

    var body: some View {
        Text(CardText.initial(player?.name ?? "?"))
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(Theme.playerColor(player), in: Circle())
            .accessibilityHidden(true)
    }
}

struct Pill: View {
    let text: String
    var tint: Color = Theme.ink
    var background: Color = Theme.sunk

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}

struct MutualButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet, danger }

    var kind: Kind = .primary
    var wide = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(kind == .primary ? Theme.accentInk : kind == .danger ? Vote.never.color : Theme.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(kind == .primary ? Theme.accent : kind == .danger ? Vote.never.soft : Theme.sunk, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == MutualButtonStyle {
    static func mutual(_ kind: MutualButtonStyle.Kind = .primary, wide: Bool = false) -> MutualButtonStyle {
        MutualButtonStyle(kind: kind, wide: wide)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
    }
}

/// Lays out chips left to right, wrapping onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if x > 0 && x + size.width > width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            size.width = min(size.width, bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A labeled text field in the artifact's style.
struct Field: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var axis: Axis = .horizontal
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(axis == .vertical ? 3...8 : 1...1)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .URL)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1.5))
                .accessibilityLabel(label)
        }
    }
}
