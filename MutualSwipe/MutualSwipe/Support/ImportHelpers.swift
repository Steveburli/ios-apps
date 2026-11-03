import SwiftUI
import UIKit
import Vision
import MutualKit

/// Reads the words in a photo, top to bottom, one line of text per line.
enum TextReader {
    static func read(_ image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                try? handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The camera, for photographing a menu or a list on paper.
struct CameraPicker: UIViewControllerRepresentable {
    let onDone: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onDone: (UIImage?) -> Void

        init(onDone: @escaping (UIImage?) -> Void) {
            self.onDone = onDone
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onDone(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onDone(nil)
        }
    }
}

extension Session {
    /// Text waiting to become cards: a file opened in Mutual from another app.
    struct PendingImport {
        let text: String
        /// The file's name without its extension, offered as the new deck's name.
        let name: String
        let isCSV: Bool

        init(text: String, name: String, isCSV: Bool) {
            self.text = text
            self.name = name
            self.isCSV = isCSV
        }

        /// Reads a CSV or text file, from the file picker or from another app.
        init?(fileURL url: URL) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), data.count < 5_000_000 else { return nil }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else { return nil }
            let ext = url.pathExtension.lowercased()
            self.init(text: text, name: url.deletingPathExtension().lastPathComponent, isCSV: ext == "csv" || ext == "tsv")
        }
    }
}
