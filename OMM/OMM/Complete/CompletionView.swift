import SwiftUI

struct CompletionView: View {
    @Environment(AppModel.self) private var model
    let days: Int

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                Card {
                    VStack(spacing: 0) {
                        Text("🎉")
                            .font(.system(size: 96))
                            .accessibilityHidden(true)
                        Text("Program Complete!")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(Theme.primary)
                            .padding(.top, 18)
                            .padding(.bottom, 10)
                            .accessibilityAddTraits(.isHeader)
                        Text("You completed the entire program in \(days.counted("day"))!")
                            .font(.title3)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 26)
                        Button("Back to Home") { model.goHome() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.top, 20)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: 560)
                // Centered on the screen, but still scrolls with very large text.
                .frame(maxWidth: .infinity, minHeight: proxy.size.height * 0.85)
            }
        }
    }
}
