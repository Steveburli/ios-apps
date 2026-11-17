import SwiftUI
import MutualKit

/// Photos bundled with the starter decks. A card shows one when it came from a
/// starter deck (matched by its website, see `Starter.match`). Cards without a
/// photo keep their color and initial.
enum StarterPhoto {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(named name: String?) -> UIImage? {
        guard let name else { return nil }
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// A plan card uses its first photo that's already on the phone.
    @MainActor
    static func image(for card: Card) -> UIImage? {
        if let plan = card.plan { return PlanPhotos.cover(of: plan) }
        return image(named: Starter.match(card)?.photoName)
    }
}

/// A small square: the starter photo, or the card's color and initial.
struct CardThumb: View {
    let title: String
    let colorID: String
    var photo: UIImage?
    var size: CGFloat = 34

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(CardText.initial(title))
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.cardColor(colorID))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}
