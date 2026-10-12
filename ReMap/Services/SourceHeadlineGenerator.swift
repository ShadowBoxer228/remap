import Foundation

/// PDFKit/OCR supply evidence; OpenAI chooses the study concepts through the private gateway.
enum SourceHeadlineGenerator {
    private struct Request: Encodable {
        let sourceId: String
        let title: String
        let pages: [NativeSourceMaterial.Page]
    }
    struct Topic: Codable { let label: String; let page: Int; let quote: String }
    struct Reply: Decodable { let headlines: [Topic] }

    static func headlines(from material: NativeSourceMaterial) async throws -> [Headline] {
        let request = Request(sourceId: material.id, title: material.title, pages: material.pages)
        let data = try await LocalCoachGateway.post(path: "api/native/headlines", body: JSONEncoder().encode(request), timeout: 65)
        return try validatedHeadlines(try JSONDecoder().decode(Reply.self, from: data).headlines, material: material)
    }

    static func validatedHeadlines(_ topics: [Topic], material: NativeSourceMaterial) throws -> [Headline] {
        guard (6...24).contains(topics.count) else { throw LocalCoachFailure.message("OpenAI returned an incomplete topic list. Retry PDF preparation.") }
        var labels = Set<String>()
        return try topics.map { topic in
            let label = topic.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, label.count <= 80, labels.insert(NativeSourceMaterial.normalized(label)).inserted,
                  material.validatedReferences([LocalCoachReference(page: topic.page, reason: topic.quote, quote: topic.quote)]).count == 1 else {
                throw LocalCoachFailure.message("A generated topic could not be verified in this PDF. Retry PDF preparation.")
            }
            return Headline(text: label, page: topic.page)
        }
    }
}
