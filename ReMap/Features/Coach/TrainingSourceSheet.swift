import SwiftUI
import PDFKit

struct TrainingSourceSheet: View {
    var session: StudySession
    var page: Int
    var passages: [LocalSourceResult.Passage]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text(session.isTrainingDemo ? TrainingLLMContent.attribution : session.source.name).font(.caption).padding(.horizontal)
                TrainingPDFPage(url: app.sourceURL(for: session), page: page)
                if let passage = passages.first(where: { $0.page == page }) {
                    DisclosureGroup("Extracted text · page \(page)") {
                        ScrollView { Text(passage.text).textSelection(.enabled).padding() }.frame(maxHeight: 180)
                    }.padding(.horizontal)
                }
            }
            .navigationTitle("Source · page \(page)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct TrainingPDFPage: UIViewRepresentable {
    let url: URL?
    let page: Int
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePage
        view.document = SourcePageDocument.make(url: url, page: page)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        let identity = "\(url?.absoluteString ?? "")#\(page)"
        if context.coordinator.identity != identity {
            context.coordinator.identity = identity
            view.document = SourcePageDocument.make(url: url, page: page)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var identity = "" }
}

enum SourcePageDocument {
    /// PDFKit can reset an early go(to:) during sheet layout. A single-page document
    /// guarantees that the cited physical page is the one displayed, including on iPadOS 17.
    static func make(url: URL?, page: Int) -> PDFDocument? {
        guard let url, let original = PDFDocument(url: url), page > 0,
              let selected = original.page(at: page - 1)?.copy() as? PDFPage else { return nil }
        let document = PDFDocument(); document.insert(selected, at: 0)
        return document
    }
}
