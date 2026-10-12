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
        let view = PDFView(); view.autoScales = true
        if let url {
            view.document = PDFDocument(url: url)
        }
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = url.flatMap { PDFDocument(url: $0) } }
        if let document = view.document, let target = document.page(at: max(0, min(page - 1, document.pageCount - 1))) {
            view.go(to: target)
        }
    }
}
