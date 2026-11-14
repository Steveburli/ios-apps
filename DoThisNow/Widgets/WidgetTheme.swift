import SwiftUI
import UIKit

/// The app's colors (Support/Theme.swift), copied for the widgets extension.
enum WidgetTheme {
    static let bg = Color(lightHex: 0xECEFEA, darkHex: 0x111412)
    static let surface = Color(lightHex: 0xF9FBF7, darkHex: 0x1A1E1B)
    static let ink = Color(lightHex: 0x191D1A, darkHex: 0xECF0EB)
    static let ink2 = Color(lightHex: 0x4C544E, darkHex: 0xB1BAB3)
    static let line = Color(lightHex: 0xD2D8D0, darkHex: 0x2E3531)
    static let accent = Color(lightHex: 0xE0431C, darkHex: 0xFF6A44)
    static let accentInk = Color(lightHex: 0xFFFFFF, darkHex: 0x1A0904)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    /// "4:05" or "1:02:30".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension Color {
    init(lightHex: UInt32, darkHex: UInt32) {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? color(darkHex) : color(lightHex)
        })
    }
}
