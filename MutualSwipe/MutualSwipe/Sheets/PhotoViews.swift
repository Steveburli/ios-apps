import SwiftUI
import MutualKit

/// One added photo as a rounded square. A gray box while it's still downloading.
struct PhotoTile: View {
    let id: String
    var size: CGFloat = 96

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Group {
            if let image = PhotoFiles.image(for: id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.sunk.overlay { ProgressView() }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// A card's photos full screen, swiping sideways between them.
struct PhotoPager: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [CardPhoto]
    @State private var current: String

    init(photos: [CardPhoto], startID: String) {
        self.photos = photos
        _current = State(initialValue: startID)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(photos) { photo in
                    Group {
                        if let image = PhotoFiles.image(for: photo.id) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        if !photo.addedBy.isEmpty {
                            Text("Added by \(photo.addedBy)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.bottom, 40)
                        }
                    }
                    .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.white.opacity(0.2), in: Circle())
            }
            .accessibilityLabel("Close")
            .padding(16)
        }
    }
}
