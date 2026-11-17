import SwiftUI
import UIKit
import MutualKit

/// Photos added to plans from a phone. Each is a JPEG in Application Support,
/// synced to everyone in the group as a CloudKit asset on the card.
enum PlanPhotoStore {
    static let folder: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("PlanPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private static let cache = NSCache<NSString, UIImage>()

    static func url(for name: String) -> URL {
        folder.appendingPathComponent(name)
    }

    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    /// Shrinks the photo to at most 1600 points on its long side and saves it.
    /// Returns its `photo:` reference.
    static func save(_ image: UIImage) -> String? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.78) else { return nil }
        let name = makeID() + ".jpg"
        do {
            try data.write(to: url(for: name), options: .atomic)
        } catch {
            return nil
        }
        cache.setObject(resized, forKey: name as NSString)
        return PhotoRef.phone(name).string
    }

    static func image(named name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let image = UIImage(contentsOfFile: url(for: name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Keeps a copy of a photo that arrived from iCloud, under its plan name.
    static func adopt(_ file: URL, as name: String) {
        let target = url(for: name)
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        try? FileManager.default.copyItem(at: file, to: target)
    }

    /// The `photo:` file names in a plan, in order.
    static func names(in plan: Itinerary) -> [String] {
        plan.photos.compactMap { raw in
            if case .phone(let name)? = PhotoRef(raw) { return name }
            return nil
        }
    }
}

/// Photos from places' websites, loaded once and kept in memory.
@MainActor
final class WebPhotoCache {
    static let shared = WebPhotoCache()
    private let cache = NSCache<NSURL, UIImage>()
    private var failed: Set<URL> = []

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func load(_ url: URL) async -> UIImage? {
        if let hit = image(for: url) { return hit }
        guard !failed.contains(url) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
              data.count < 15_000_000,
              let image = UIImage(data: data) else {
            failed.insert(url)
            return nil
        }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1400 / max(longest, 1))
        let small = await image.byPreparingThumbnail(ofSize: CGSize(width: image.size.width * scale,
                                                                    height: image.size.height * scale)) ?? image
        cache.setObject(small, forKey: url as NSURL)
        return small
    }
}

enum PlanPhotos {
    /// The photo right away, when it's on the phone already.
    @MainActor
    static func immediate(_ raw: String) -> UIImage? {
        switch PhotoRef(raw) {
        case .starter(let id)?: return StarterPhoto.image(named: "starter-" + id)
        case .phone(let name)?: return PlanPhotoStore.image(named: name)
        case .web(let url)?: return WebPhotoCache.shared.image(for: url)
        case nil: return nil
        }
    }

    /// The first photo that's ready without the network, for small thumbnails.
    @MainActor
    static func cover(of plan: Itinerary?) -> UIImage? {
        guard let plan else { return nil }
        return plan.photos.lazy.compactMap { immediate($0) }.first
    }
}

/// One plan photo filling its frame.
struct PlanPhoto: View {
    let ref: String
    @State private var loaded: UIImage?
    @State private var gaveUp = false

    var body: some View {
        GeometryReader { box in
            if let image = loaded ?? PlanPhotos.immediate(ref) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: box.size.width, height: box.size.height)
                    .clipped()
            } else {
                ZStack {
                    Color.black.opacity(0.18)
                    if gaveUp {
                        Image(systemName: "photo").font(.title).foregroundStyle(Color.white.opacity(0.6))
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: box.size.width, height: box.size.height)
            }
        }
        .accessibilityHidden(true)
        .task(id: ref) {
            guard PlanPhotos.immediate(ref) == nil else { return }
            if case .web(let url)? = PhotoRef(ref) {
                loaded = await WebPhotoCache.shared.load(url)
            }
            gaveUp = loaded == nil
        }
    }
}

/// Photos side by side that swipe sideways one at a time, with a bar per
/// photo along the top. Sideways drags here page the photos instead of
/// voting on the card. With one photo there's nothing to page, so drags
/// pass through to the card.
struct PlanPhotoPager: View {
    let photos: [String]
    var barsInset: CGFloat = 10
    @State private var page = 0
    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { box in
            let width = box.size.width
            HStack(spacing: 0) {
                ForEach(Array(photos.enumerated()), id: \.offset) { _, ref in
                    PlanPhoto(ref: ref)
                        .frame(width: width, height: box.size.height)
                }
            }
            .offset(x: -CGFloat(min(page, max(0, photos.count - 1))) * width + drag)
            .frame(width: width, height: box.size.height, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(pageGesture(width: width), including: photos.count > 1 ? .all : .subviews)
        }
        .overlay(alignment: .top) {
            if photos.count > 1 {
                HStack(spacing: 4) {
                    ForEach(photos.indices, id: \.self) { index in
                        Capsule()
                            .fill(Color.white.opacity(index == page ? 0.95 : 0.4))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, barsInset)
                .padding(.top, 8)
                .shadow(color: .black.opacity(0.25), radius: 2)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: photos) { _, list in page = min(page, max(0, list.count - 1)) }
        .accessibilityElement()
        .accessibilityLabel(photos.isEmpty ? "No photos" : "Photo \(page + 1) of \(photos.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page = min(photos.count - 1, page + 1)
            case .decrement: page = max(0, page - 1)
            @unknown default: break
            }
        }
    }

    private func pageGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let dx = value.translation.width
                let atEdge = (page == 0 && dx > 0) || (page == photos.count - 1 && dx < 0)
                drag = atEdge ? dx / 3 : dx
            }
            .onEnded { value in
                let dx = value.translation.width
                let projected = value.predictedEndTranslation.width
                var next = page
                if dx < -width * 0.2 || projected < -width * 0.5 { next += 1 }
                if dx > width * 0.2 || projected > width * 0.5 { next -= 1 }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    page = max(0, min(photos.count - 1, next))
                    drag = 0
                }
            }
    }
}
