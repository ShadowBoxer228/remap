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
    func validatedReferences(_ references: [LocalCoachReference]) -> [LocalCoachReference] {
        var seen = Set<Int>()
        return references.prefix(3).filter { reference in
            guard let quote = reference.quote, (2...240).contains(quote.count),
                  let page = pages.first(where: { $0.page == reference.page }),
                  Self.normalized(page.text).contains(Self.normalized(quote)),
                  !Self.normalized(quote).isEmpty else { return false }
            return seen.insert(reference.page).inserted
        }
    }
    static func normalized(_ value: String) -> String {
        value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    func matching(_ query: String, pages requested: [Int], history: [String] = []) -> [Page] {
        var requested = requested
        if let expression = try? NSRegularExpression(pattern: #"(?i)(?:page|p\.|стр(?:аница)?\.?|sayfa)\s*(\d{1,3})"#) {
            let range = NSRange(query.startIndex..., in: query)
            requested += expression.matches(in: query, range: range).compactMap { result in
                Range(result.range(at: 1), in: query).flatMap { Int(query[$0]) }
            }
        }
        let terms = Set(query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        let previous = Set(history.joined(separator: " ").lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        func phrases(_ value: String) -> [String] {
            let words = Self.normalized(value).split(separator: " ").map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            return zip(words, words.dropFirst()).map { $0 + " " + $1 }
        }
        let currentPhrases = phrases(query)
        let previousPhrases = history.flatMap(phrases)
        func score(_ page: Page) -> Int {
            let text = Self.normalized(page.text)
            return (requested.contains(page.page) ? 10000 : 0)
                + terms.reduce(0) { $0 + (text.contains($1) ? 3 : 0) }
                + previous.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
                + currentPhrases.reduce(0) { $0 + (text.contains($1) ? 6 : 0) }
                + previousPhrases.reduce(0) { $0 + (text.contains($1) ? 2 : 0) }
        }
        return pages.sorted { score($0) == score($1) ? $0.page < $1.page : score($0) > score($1) }
            .prefix(4).map { Page(page: $0.page, text: String($0.text.prefix(5000))) }
    }
}

@MainActor private enum NativeSourceCache {
    static var demo: NativeSourceMaterial?
    static let images: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>(); cache.countLimit = 12; return cache
    }()
}
extension SessionModel {
    /// Bounded, cached page image retains tables/diagrams that plain PDF text flattens.
    func sourcePageImage(_ number: Int) -> String? {
        guard (1...30).contains(number), let sourceID = session.localCoachSourceID else { return nil }
        let key = "\(sourceID)-\(number)" as NSString
        if let cached = NativeSourceCache.images.object(forKey: key) { return cached as String }
        let url = session.isTrainingDemo ? Bundle.main.url(forResource: TrainingLLMContent.pdfName, withExtension: "pdf")
            : session.source.fileName.map { SessionStore.sourcesDirectory.appending(path: $0) }
        guard let url, let page = PDFDocument(url: url)?.page(at: number - 1),
              let bytes = page.thumbnail(of: CGSize(width: 1536, height: 1536), for: .mediaBox).jpegData(compressionQuality: 0.7),
              bytes.count <= 360_000 else { return nil }
        let image = "data:image/jpeg;base64," + bytes.base64EncodedString()
        NativeSourceCache.images.setObject(image as NSString, forKey: key)
        return image
    }
    func prepareCoachSource() async throws {
        guard session.usesPDFCoach else { return }
        if localSourceMaterial() != nil { return }
        let source = session.source
        let url: URL?
        if session.isTrainingDemo { url = Bundle.main.url(forResource: TrainingLLMContent.pdfName, withExtension: "pdf") }
        else { url = source.fileName.map { SessionStore.sourcesDirectory.appending(path: $0) } }
        guard let url else { throw IngestionError.unreadablePDF }
        let material = try await Task.detached(priority: .userInitiated) {
            try NativeSourceMaterial.read(url: url, title: source.name)
        }.value
        try Task.checkCancellation()
        guard session.source.fileName == source.fileName, session.source.name == source.name else { throw CancellationError() }
        if session.isTrainingDemo { NativeSourceCache.demo = material }
        else {
            let data = try JSONEncoder().encode(material)
            update { $0.source.text = String(data: data, encoding: .utf8); $0.source.sourceId = material.id; $0.source.pageCount = material.pages.count }
        }
    }

    func localSourceMaterial() -> NativeSourceMaterial? {
        if let text = session.source.text, let bytes = text.data(using: .utf8),
           let material = try? JSONDecoder().decode(NativeSourceMaterial.self, from: bytes) { return material }
        if session.isTrainingDemo {
            if let material = NativeSourceCache.demo { return material }
            return nil
        }
        return nil
    }
}
