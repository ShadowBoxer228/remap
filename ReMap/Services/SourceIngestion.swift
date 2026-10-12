import Foundation
import PDFKit
import UIKit

/// Turns a study source into a list of headlines for priming.
/// PDFs register with the connected engine; other legacy source types retain local extraction.
protocol SourceIngesting {
    func headlines(for source: SourceInfo) async throws -> [Headline]
    func ingest(_ source: SourceInfo) async throws -> SourceIngestionResult
}

struct SourceIngestionResult {
    let headlines: [Headline]
    let sourceId: String?
    let pageCount: Int?
    let warnings: [String]
    var sourceText: String? = nil
}

extension SourceIngesting {
    func ingest(_ source: SourceInfo) async throws -> SourceIngestionResult {
        SourceIngestionResult(headlines: try await headlines(for: source), sourceId: source.sourceId,
                              pageCount: source.pageCount, warnings: [])
    }
}

nonisolated enum IngestionError: LocalizedError {
    case unreadablePDF
    case needsBackend

    var errorDescription: String? {
        switch self {
        case .unreadablePDF: String(localized: "This PDF couldn't be read.")
        case .needsBackend: String(localized: "Automatic transcripts arrive with the AI backend. Paste the transcript or add headlines yourself.")
        }
    }
}

nonisolated private struct LocalPDFUploadRequest: Encodable { let name: String; let pdfBase64: String }

struct LocalSourceIngestor: SourceIngesting {
    func ingest(_ source: SourceInfo) async throws -> SourceIngestionResult {
        guard source.kind == .pdf, source.usesLearningEngine == true else {
            return SourceIngestionResult(headlines: try await headlines(for: source), sourceId: source.sourceId,
                                         pageCount: source.pageCount, warnings: [])
        }
        guard let name = source.fileName else { throw IngestionError.unreadablePDF }
        let url = SessionStore.sourcesDirectory.appending(path: name)
        return try await Task.detached(priority: .userInitiated) {
            let material = try NativeSourceMaterial.read(url: url, title: source.name)
            var headings = try? await Self.fromPDF(at: url)
            if headings?.isEmpty != false {
                headings = material.pages.flatMap { page in
                    TextHeadlineExtractor.headlines(from: page.text).prefix(2).map {
                        Headline(text: $0.text, page: page.page)
                    }
                }
            }
            let encoded = try JSONEncoder().encode(material)
            return SourceIngestionResult(headlines: Array((headings ?? []).prefix(40)),
                sourceId: material.id, pageCount: material.pages.count,
                warnings: material.pages.allSatisfy { $0.text.isEmpty } ? ["No readable text found. Add keywords manually; the original PDF is preserved."] : [],
                sourceText: String(data: encoded, encoding: .utf8))
        }.value
    }

    func headlines(for source: SourceInfo) async throws -> [Headline] {
        switch source.kind {
        case .demo:
            if source.name == "TrainingLLM.pdf" { return TrainingLLMContent.headlines() }
            if let url = Bundle.main.url(forResource: DemoContent.pdfName, withExtension: "pdf"),
               let extracted = try? await Self.fromPDF(at: url), !extracted.isEmpty {
                return extracted
            }
            return DemoContent.headlines()
        case .pdf:
            guard let name = source.fileName else { throw IngestionError.unreadablePDF }
            return try await Self.fromPDF(at: SessionStore.sourcesDirectory.appending(path: name))
        case .text:
            return TextHeadlineExtractor.headlines(from: source.text ?? "")
        case .youtube:
            if let text = source.text, !text.isEmpty { return TextHeadlineExtractor.headlines(from: text) }
            throw IngestionError.needsBackend
        }
    }

    static func fromPDF(at url: URL) async throws -> [Headline] {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else { throw IngestionError.unreadablePDF }
            let outline = PDFOutlineExtractor.outline(of: document)
            return outline.isEmpty ? PDFOutlineExtractor.headingsByFontSize(in: document) : outline
        }.value
    }
}

nonisolated enum PDFOutlineExtractor {
    /// Walks the PDF's table of contents.
    static func outline(of document: PDFDocument) -> [Headline] {
        guard let root = document.outlineRoot else { return [] }
        var result: [Headline] = []
        func walk(_ item: PDFOutline, level: Int) {
            for i in 0..<item.numberOfChildren {
                guard let child = item.child(at: i) else { continue }
                if let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                    let page = child.destination?.page.map { document.index(for: $0) + 1 }
                    result.append(Headline(text: label, page: page, level: level))
                }
                if level < 2 { walk(child, level: level + 1) }
            }
        }
        walk(root, level: 0)
        return Array(result.prefix(40))
    }

    /// No outline: treat lines set noticeably larger (or bold) than the body text as headings.
    static func headingsByFontSize(in document: PDFDocument, maxPages: Int = 30) -> [Headline] {
        struct Line { var text: String; var size: CGFloat; var bold: Bool; var page: Int }
        var lines: [Line] = []
        for p in 0..<min(document.pageCount, maxPages) {
            guard let attributed = document.page(at: p)?.attributedString else { continue }
            let string = attributed.string as NSString
            var location = 0
            while location < string.length {
                let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
                let text = string.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, lineRange.length > 0 {
                    var maxSize: CGFloat = 0
                    var bold = false
                    attributed.enumerateAttribute(.font, in: lineRange) { value, _, _ in
                        if let font = value as? UIFont {
                            maxSize = max(maxSize, font.pointSize)
                            bold = bold || font.fontDescriptor.symbolicTraits.contains(.traitBold)
                        }
                    }
                    lines.append(Line(text: text, size: maxSize, bold: bold, page: p + 1))
                }
                location = NSMaxRange(lineRange)
            }
        }
        let sizes = lines.map(\.size).sorted()
        guard !sizes.isEmpty else { return [] }
        let median = sizes[sizes.count / 2]
        var seen = Set<String>()
        return lines.filter { line in
            let words = line.text.split(separator: " ").count
            let looksLikeHeading = line.size >= median * 1.2 || (line.bold && words <= 8)
            return looksLikeHeading && words <= 10 && line.text.count >= 3 && seen.insert(line.text.lowercased()).inserted
        }
        .prefix(40)
        .map { Headline(text: $0.text, page: $0.page, level: $0.size >= median * 1.5 ? 0 : 1) }
    }
}

/// Headlines from pasted notes or a transcript: markdown/numbered headings and short title-like
/// lines first; otherwise the opening phrase of each paragraph.
nonisolated enum TextHeadlineExtractor {
    static func headlines(from text: String) -> [Headline] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var result: [Headline] = []
        var seen = Set<String>()
        func add(_ raw: String, level: Int) {
            let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#*-•:. \t0123456789)"))
            guard cleaned.count >= 3, seen.insert(cleaned.lowercased()).inserted else { return }
            result.append(Headline(text: cleaned, level: level))
        }
        for line in lines {
            if line.hasPrefix("#") {
                add(line, level: line.prefix(while: { $0 == "#" }).count > 1 ? 1 : 0)
            } else if line.range(of: #"^\d+[\.\)]\s"#, options: .regularExpression) != nil, line.split(separator: " ").count <= 8 {
                add(line, level: 0)
            } else if line.split(separator: " ").count <= 6, !line.hasSuffix("."), line.first?.isUppercase == true {
                add(line, level: 1)
            }
        }
        if result.count < 3 {
            for paragraph in text.components(separatedBy: "\n\n") {
                let firstSentence = paragraph.split(whereSeparator: { ".!?".contains($0) }).first.map(String.init) ?? paragraph
                let words = firstSentence.split(separator: " ").prefix(5).joined(separator: " ")
                if !words.isEmpty { add(words, level: 1) }
            }
        }
        return Array(result.prefix(40))
    }
}
