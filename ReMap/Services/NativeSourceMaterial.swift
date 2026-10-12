import Foundation
import PDFKit
import UIKit
import Vision
import CryptoKit

nonisolated struct NativeSourceMaterial: Codable, Sendable {
    struct Page: Codable, Sendable { let page: Int; let text: String }
    let id: String
    let title: String
    let pages: [Page]
    static func read(url: URL, title: String) throws -> Self {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 20 * 1024 * 1024,
              let document = PDFDocument(url: url), !document.isLocked,
              (1...30).contains(document.pageCount) else {
            throw LocalCoachFailure.message("Choose an unlocked PDF up to 20 MB and 30 pages.")
        }
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        var pages: [Page] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            var text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.count < 20, let image = page.thumbnail(of: CGSize(width: 1400, height: 1800), for: .mediaBox).cgImage {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: image).perform([request])
                text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            pages.append(Page(page: index + 1, text: String(text.prefix(8000))))
        }
        return Self(id: "pdf-" + digest, title: String(title.prefix(200)), pages: pages)
    }
    func matching(_ query: String, pages requested: [Int]) -> [Page] {
        let terms = Set(query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        func score(_ page: Page) -> Int {
            (requested.contains(page.page) ? 10000 : 0) + terms.reduce(0) { $0 + (page.text.lowercased().contains($1) ? 1 : 0) }
        }
        return pages.sorted { score($0) == score($1) ? $0.page < $1.page : score($0) > score($1) }
            .prefix(4).map { Page(page: $0.page, text: String($0.text.prefix(5000))) }
    }
}

@MainActor private enum NativeSourceCache { static var demo: NativeSourceMaterial? }
extension SessionModel {
    func localSourceMaterial() -> NativeSourceMaterial? {
        if let text = session.source.text, let bytes = text.data(using: .utf8),
           let material = try? JSONDecoder().decode(NativeSourceMaterial.self, from: bytes) { return material }
        if session.isTrainingDemo {
            if let material = NativeSourceCache.demo { return material }
            guard let url = Bundle.main.url(forResource: TrainingLLMContent.pdfName, withExtension: "pdf"),
                  let material = try? NativeSourceMaterial.read(url: url, title: TrainingLLMContent.title) else { return nil }
            NativeSourceCache.demo = material
            return material
        }
        return nil
    }
}
