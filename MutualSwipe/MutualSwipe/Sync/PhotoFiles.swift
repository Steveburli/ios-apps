import UIKit
import MutualKit

/// Card photos on this phone: one small JPEG per photo in Application Support,
/// named `<photo id>.jpg`. The same file is sent to iCloud as the record's asset.
enum PhotoFiles {
    private static let cache = NSCache<NSString, UIImage>()

    static let folder: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("card-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    static func url(for id: String) -> URL {
        folder.appendingPathComponent(id + ".jpg")
    }

    static func exists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    static func image(for id: String) -> UIImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url(for: id).path) else { return nil }
        cache.setObject(image, forKey: id as NSString)
        return image
    }

    /// Shrinks a picked photo and saves it. Returns false if it couldn't be read.
    static func save(_ image: UIImage, as id: String) -> Bool {
        guard let data = shrunkJPEG(image) else { return false }
        return write(data, as: id)
    }

    @discardableResult
    static func write(_ data: Data, as id: String) -> Bool {
        do {
            try data.write(to: url(for: id), options: .atomic)
            cache.removeObject(forKey: id as NSString)
            return true
        } catch {
            return false
        }
    }

    /// Copies the file iCloud downloaded, which is only kept until the sync event ends.
    static func copy(from source: URL, as id: String) {
        guard let data = try? Data(contentsOf: source) else { return }
        write(data, as: id)
    }

    static func remove(_ id: String) {
        try? FileManager.default.removeItem(at: url(for: id))
        cache.removeObject(forKey: id as NSString)
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cache.removeAllObjects()
    }

    /// At most `CardPhotos.maxPixels` on the longest side, as a JPEG.
    static func shrunkJPEG(_ image: UIImage) -> Data? {
        let pixelWidth = Double(image.size.width * image.scale)
        let pixelHeight = Double(image.size.height * image.scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let size = CardPhotos.fittedSize(width: pixelWidth, height: pixelHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width, height: size.height), format: format)
        return renderer.jpegData(withCompressionQuality: 0.72) { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
    }
}
