import SwiftUI
import UIKit

/// The web app's palette, light and dark. Each block on the Day view is a
/// material: rock (work), soft clay (tasks), jelly with a hard core (events),
/// night (sleep).
enum Theme {
    static let bg = Color(light: 0xECEFEA, dark: 0x111412)
    static let surface = Color(light: 0xF9FBF7, dark: 0x1A1E1B)
    static let surface2 = Color(light: 0xE1E6DF, dark: 0x252B27)
    static let ink = Color(light: 0x191D1A, dark: 0xECF0EB)
    static let ink2 = Color(light: 0x4C544E, dark: 0xB1BAB3)
    static let ink3 = Color(light: 0x7A837C, dark: 0x848D86)
    static let line = Color(light: 0xD2D8D0, dark: 0x2E3531)
    static let accent = Color(light: 0xE0431C, dark: 0xFF6A44)
    static let accentInk = Color(light: 0xFFFFFF, dark: 0x1A0904)
    static let accentWash = Color(light: 0xF9D8CC, dark: 0x3E2017)
    static let rock = Color(light: 0x7B8189, dark: 0x5B6168)
    static let rockInk = Color(light: 0xFFFFFF, dark: 0xF2F4F6)
    static let soft = Color(light: 0xF6C7A0, dark: 0x7E4F2C)
    static let softInk = Color(light: 0x4A2810, dark: 0xFFE8D6)
    static let softLine = Color(light: 0xE0A06E, dark: 0xA8693A)
    static let jelly = Color(light: 0x7048E8, dark: 0x9676FF, lightAlpha: 0.15, darkAlpha: 0.18)
    static let jellyLine = Color(light: 0x7048E8, dark: 0x9676FF, lightAlpha: 0.48, darkAlpha: 0.55)
    /// Blocks you placed yourself: firm, but they shove each other.
    static let block = Color(light: 0x1C7287, dark: 0x3FA6BB)
    static let blockInk = Color(light: 0xFFFFFF, dark: 0x04161B)
    static let core = Color(light: 0x6842DD, dark: 0x8B6BFF)
    static let coreInk = Color(light: 0xFFFFFF, dark: 0x0F0726)
    static let meal = Color(light: 0xF1D263, dark: 0x7C6A18)
    static let mealInk = Color(light: 0x3B3000, dark: 0xFFF4C4)
    static let sleep = Color(light: 0x2B3070, dark: 0x252A66)
    static let sleepInk = Color(light: 0xE4E6FF, dark: 0xDADDFF)
    static let good = Color(light: 0x23804F, dark: 0x5BC98C)
    static let warn = Color(light: 0xA86F00, dark: 0xE0A83A)
    static let bad = Color(light: 0xC8352E, dark: 0xFF6B61)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static let hero = display(40)
}

extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Controls

struct DTNButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, quiet, danger }
    enum Size { case small, regular, big }

    var kind: Kind = .normal
    var size: Size = .regular
    var wide = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let radius: CGFloat = size == .big ? 16 : size == .small ? 10 : 12
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let font: Font
        switch size {
        case .big: font = .system(size: 18, weight: .bold, design: .rounded)
        case .small: font = .footnote.weight(.semibold)
        case .regular: font = .subheadline.weight(.semibold)
        }
        return configuration.label
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .small ? 12 : 16)
            .padding(.vertical, size == .small ? 6 : 9)
            .frame(minHeight: size == .big ? 58 : size == .small ? 36 : 44)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(background, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1.5))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(shape)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Theme.accentInk
        case .danger: return Theme.bad
        default: return Theme.ink
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.accent
        case .quiet: return .clear
        default: return Theme.surface
        }
    }

    private var border: Color {
        switch kind {
        case .primary: return Theme.accent
        case .quiet: return .clear
        default: return Theme.line
        }
    }
}

extension ButtonStyle where Self == DTNButtonStyle {
    static func dtn(_ kind: DTNButtonStyle.Kind = .normal, size: DTNButtonStyle.Size = .regular, wide: Bool = false) -> DTNButtonStyle {
        DTNButtonStyle(kind: kind, size: size, wide: wide)
    }
}

/// A pill you pick from, like the web app's chips.
struct Chip: View {
    let title: String
    var subtitle: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: subtitle == nil ? 20 : 14, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(isOn ? Theme.surface2 : Theme.ink3)
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(isOn ? Theme.bg : Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 40)
            .background(isOn ? Theme.ink : Theme.surface, in: shape)
            .overlay(shape.strokeBorder(isOn ? Theme.ink : Theme.line, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
    }
}

/// The soft grey box used for banners.
struct BannerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardModifier(padding: padding)) }
    func banner() -> some View { modifier(BannerModifier()) }
}

/// A small rounded label: "Due tomorrow", "Errand · Library".
struct Tag: View {
    enum Tone { case plain, warn, bad, example, hot }

    let text: String
    var tone: Tone = .plain

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(tone == .bad ? Theme.surface : tone == .warn || tone == .hot ? Theme.ink : Theme.ink2)
            .background(background, in: Capsule())
            .overlay {
                if tone == .example {
                    Capsule().strokeBorder(Theme.ink3, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
    }

    private var background: Color {
        switch tone {
        case .plain: return Theme.surface2
        case .warn, .hot: return Theme.accentWash
        case .bad: return Theme.bad
        case .example: return .clear
        }
    }
}

/// A question label over a group of chips.
struct Question<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            FlowLayout {
                content
            }
        }
    }
}
