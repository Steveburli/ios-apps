import SwiftUI
import UIKit
import ArgumentKit

/// Map My Argument's palette, light and dark: paper and stone, with a drafting-pencil blue
/// for actions. The same tokens as web/css/site.css.
enum Theme {
    static let bg = Color(light: 0xF1F2EE, dark: 0x0F1412)
    static let surface = Color(light: 0xFFFFFF, dark: 0x171D1A)
    static let sunk = Color(light: 0xE7E9E3, dark: 0x1F2622)
    static let ink = Color(light: 0x17201C, dark: 0xE7ECE8)
    static let muted = Color(light: 0x59635E, dark: 0x9CA59F)
    static let line = Color(light: 0xD2D6CF, dark: 0x2D3631)
    static let accent = Color(light: 0x2F45C8, dark: 0x93A3FF)
    static let accentInk = Color(light: 0xFFFFFF, dark: 0x0D1238)
    static let accentSoft = Color(light: 0xE2E6FA, dark: 0x212A57)

    static let solid = Color(light: 0x2E7D5B, dark: 0x5CC48F)
    static let strained = Color(light: 0xB37B0E, dark: 0xE2B044)
    static let sagging = Color(light: 0xC9581A, dark: 0xF08A4B)
    static let failing = Color(light: 0xC2312A, dark: 0xF2665E)
    static let solidSoft = Color(light: 0xDDEFE5, dark: 0x16322A)
    static let strainedSoft = Color(light: 0xF6EBCF, dark: 0x3A2F12)
    static let saggingSoft = Color(light: 0xF8E2D4, dark: 0x3D2416)
    static let failingSoft = Color(light: 0xF7DEDC, dark: 0x3F1B19)

    static let skyTop = Color(light: 0xD5E2EC, dark: 0x132234)
    static let skyBottom = Color(light: 0xEEF2EF, dark: 0x1A2430)
    static let stone = Color(light: 0xDDD6C7, dark: 0x8E8778)
    static let stoneEdge = Color(light: 0x8D8576, dark: 0x4D4840)
    static let stoneDark = Color(light: 0xB9B09F, dark: 0x6F695D)
    static let soil = Color(light: 0x7C6B55, dark: 0x3E3529)
    static let soilDark = Color(light: 0x6A5B47, dark: 0x30291F)
    static let cloud = Color(light: 0xFFFFFF, dark: 0xCBD5DF)
    static let cloudEdge = Color(light: 0xB8C6D3, dark: 0x8393A3)

    static let radius: CGFloat = 12

    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func color(_ status: ClaimStatus) -> Color {
        switch status {
        case .solid: return solid
        case .strained: return strained
        case .sagging: return sagging
        case .failing, .fallen: return failing
        }
    }

    static func soft(_ status: ClaimStatus) -> Color {
        switch status {
        case .solid: return solidSoft
        case .strained: return strainedSoft
        case .sagging: return saggingSoft
        case .failing, .fallen: return failingSoft
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

// MARK: - Shared pieces

/// A pediment on three pillars: the app's mark.
struct BrandMark: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 32
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(CGRect(x: x * s, y: y * s, width: w * s, height: h * s))
            }
            var roof = Path()
            roof.move(to: CGPoint(x: 3 * s, y: 11 * s))
            roof.addLine(to: CGPoint(x: 16 * s, y: 3 * s))
            roof.addLine(to: CGPoint(x: 29 * s, y: 11 * s))
            roof.closeSubpath()
            context.fill(roof, with: .color(Theme.accent))
            for r in [rect(3, 11, 26, 4), rect(6, 15, 4, 11), rect(14, 15, 4, 11), rect(22, 15, 4, 11), rect(2, 26, 28, 3)] {
                context.fill(r, with: .color(Theme.ink))
            }
        }
        .accessibilityHidden(true)
    }
}

struct Pill: View {
    let text: String
    let color: Color
    let background: Color

    init(_ text: String, color: Color, background: Color) {
        self.text = text
        self.color = color
        self.background = background
    }

    init(status: ClaimStatus) {
        self.init(status.label.uppercased(), color: Theme.color(status), background: Theme.soft(status))
    }

    var body: some View {
        Text(text)
            .font(Theme.mono(10, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .fixedSize()
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line))
    }
}

struct Notice: View {
    enum Tone { case plain, warn, bad, good }
    let title: String
    let text: String
    var detail: String = ""
    var tone: Tone = .plain

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.bold))
            Text(text).font(.subheadline)
            if !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    var background: Color {
        switch tone {
        case .plain: return Theme.sunk
        case .warn: return Theme.saggingSoft
        case .bad: return Theme.failingSoft
        case .good: return Theme.solidSoft
        }
    }
}

struct Eyebrow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(11, weight: .medium))
            .tracking(1.2)
            .foregroundStyle(Theme.muted)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 16)
            .frame(minHeight: 46)
            .frame(maxWidth: .infinity)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .background(Theme.surface.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}

extension Double {
    var percent: String { "\(Int((self * 100).rounded()))%" }
}
