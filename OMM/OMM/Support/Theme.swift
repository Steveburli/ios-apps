import SwiftUI

/// The web app's purple-blue palette.
enum Theme {
    static let primary = Color(hex: 0x667EEA)
    static let deep = Color(hex: 0x764BA2)
    static let text = Color(hex: 0x2D3748)
    static let muted = Color(hex: 0x718096)
    static let border = Color(hex: 0xE2E8F0)
    static let labelBackground = Color(hex: 0xEEF0F5)
    static let doneBackground = Color(hex: 0xE9ECF1)
    static let doneText = Color(hex: 0xA0AAB8)
    static let sheet = Color(hex: 0xF5F6FB)
    static let success = Color(hex: 0x2F855A)
    static let secondaryButton = Color(hex: 0xE2E8F0)
    static let secondaryButtonText = Color(hex: 0x4A5568)
    static let shadow = Color(hex: 0x1E1450)

    static let background = LinearGradient(colors: [primary, deep],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// A white rounded panel on the gradient.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.18), radius: 12, y: 8)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Theme.primary.opacity(isEnabled ? 0.45 : 0), radius: 7, y: 4)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(Theme.secondaryButtonText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .background(Theme.secondaryButton, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension Int {
    /// "1 day", "12 days".
    func counted(_ word: String) -> String {
        self == 1 ? "1 \(word)" : "\(self) \(word)s"
    }
}
