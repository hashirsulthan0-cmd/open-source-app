import Foundation
import ImageIO
import Vision

/// Reads text out of images with Apple's on-device Vision framework.
/// Nothing leaves the Mac.
enum TextRecognizer {
    static func recognizeText(inImageAt url: URL) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { return nil }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                return nil
            }

            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }.value
    }
}
