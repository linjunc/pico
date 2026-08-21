import Foundation
import Vision
import ImageIO

actor OCRService {
    static let shared = OCRService()
    func recognizeText(in imageData: Data) async -> String? {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil), let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text?.isEmpty == false ? text : nil)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .utility).async { try? VNImageRequestHandler(cgImage: image).perform([request]) }
        }
    }
}
