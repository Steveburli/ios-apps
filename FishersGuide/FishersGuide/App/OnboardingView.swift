import SwiftUI

/// First launch: what the guide does, why it needs location, and a safety note.
struct OnboardingView: View {
    @Environment(GuideModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                Text("Your tour guide for Fishers and Hamilton County")
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 20) {
                Point(symbol: "location.fill", title: "Stories that find you",
                      text: "Your phone's GPS knows where you are, which way you're heading and what's coming up, and starts the right story at the right moment.")
                Point(symbol: "speaker.wave.2.fill", title: "Hands-free",
                      text: "Start the tour and put the phone away. Music and podcasts dip while a story plays, and it keeps going with the screen off.")
                Point(symbol: "wifi.slash", title: "Works offline",
                      text: "Every story is on the phone, so it works on country roads with no signal.")
            }

            Spacer()

            Button {
                model.location.requestPermission()
                model.hasOnboarded = true
            } label: {
                Text("Allow Location and Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)

            Text("Location is used only on this phone to choose stories. It's never sent anywhere.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

private struct Point: View {
    var symbol: String
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
