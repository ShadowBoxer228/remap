import Foundation
import Testing
import PDFKit
@testable import ReMap

@MainActor
@Suite("PDF coach evidence and generated topics")
struct CoachSourceTests {
    let material = NativeSourceMaterial(id: "pdf-" + String(repeating: "a", count: 64), title: "Test PDF", pages: [
        .init(page: 1, text: "Pretraining learns language. Fine tuning learns instructions. Data quality matters. Neural architecture shapes computation. Evaluation measures performance. Reward modelling represents preferences."),
        .init(page: 7, text: "Instruction\n  fine-tuning uses examples.")
    ])
    @Test func quotesRequireActualPageAndText() {
        let references = [LocalCoachReference(page: 7, reason: "Heading", quote: "instruction fine-tuning"),
                          LocalCoachReference(page: 1, reason: "Wrong page", quote: "instruction fine-tuning"),
                          LocalCoachReference(page: 7, reason: "Invented", quote: "No such words")]
        #expect(material.validatedReferences(references).map(\.page) == [7])
        #expect(material.validatedReferences([.init(page: 7, reason: "Missing quote")]).isEmpty)
    }
    @Test func explicitPageRetrievalAndLegacyWorkflow() {
        #expect(material.matching("Read page 7", pages: []).first?.page == 7)
        #expect(material.matching("страница 7", pages: []).first?.page == 7)
        let session = StudySession(title: "Old map", source: .init(kind: .pdf, name: "Old.pdf"), map: MindMap(title: "Old map"))
        #expect(session.usesPDFCoach)
        #expect(!session.usesLocalCoach)
        #expect(session.canBeginBackbone)
    }
    @Test func followUpRetainsRelevantSource() {
        #expect(material.matching("Please give me the answer now", pages: [], history: ["Explain instruction fine-tuning"]).first?.page == 7)
        #expect(material.matching("Read page 1", pages: [], history: ["Explain instruction fine-tuning"]).first?.page == 1)
    }
    @Test func citedPDFContainsTheRequestedPage() throws {
        let url = try #require(Bundle.main.url(forResource: TrainingLLMContent.pdfName, withExtension: "pdf"))
        let document = try #require(SourcePageDocument.make(url: url, page: 7))
        #expect(document.pageCount == 1)
        #expect(document.string?.contains("fine-tuning") == true)
        #expect(document.string?.contains("Introduction to LLM development") == false)
        #expect(SourcePageDocument.make(url: url, page: 0) == nil)
        #expect(SourcePageDocument.make(url: url, page: 99) == nil)
    }
    @Test func generatedTopicsAreBoundedAndGrounded() throws {
        let labels = ["Pretraining", "Fine tuning", "Data quality", "Neural architecture", "Evaluation", "Reward modelling"]
        let topics = labels.map { SourceHeadlineGenerator.Topic(label: $0, page: 1, quote: $0) }
        #expect(try SourceHeadlineGenerator.validatedHeadlines(topics, material: material).count == 6)
        #expect(throws: (any Error).self) { try SourceHeadlineGenerator.validatedHeadlines(Array(topics.prefix(5)), material: material) }
        #expect(throws: (any Error).self) { try SourceHeadlineGenerator.validatedHeadlines(topics + [topics[0]], material: material) }
        #expect(throws: (any Error).self) { try SourceHeadlineGenerator.validatedHeadlines(topics.map { .init(label: $0.label, page: 99, quote: $0.quote) }, material: material) }
    }
    @Test func quoteDecodesAndRequestAdvertisesCitationTool() throws {
        let reference = try JSONDecoder().decode(LocalCoachReference.self, from: Data(#"{"page":7,"reason":"Heading","quote":"Instruction"}"#.utf8))
        #expect(reference.quote == "Instruction")
        let old = try JSONDecoder().decode(LocalCoachReference.self, from: Data(#"{"page":7,"reason":"Heading"}"#.utf8))
        #expect(old.quote == nil)
    }
}
