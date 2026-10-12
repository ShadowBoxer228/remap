import SwiftUI
import Observation

/// App-wide state: the session store, source ingestion and user preferences.
@Observable
final class AppModel {
    let store: SessionStore
    let ingestor: SourceIngesting
    var openSessionID: UUID?

    @ObservationIgnored @AppStorage("coachSpeaks") var coachSpeaks = true
    @ObservationIgnored @AppStorage("soundsOn") var soundsOn = true

    init(store: SessionStore = SessionStore(), ingestor: SourceIngesting = LocalSourceIngestor()) {
        self.store = store
        self.ingestor = ingestor
    }

    /// Creates a session and returns its id; headlines are extracted in the Collect step.
    @discardableResult
    func createSession(title: String, source: SourceInfo, isDemo: Bool = false) -> UUID {
        let session = StudySession(title: title, source: source, map: MindMap(title: title), isDemo: isDemo)
        store.add(session)
        return session.id
    }

    @discardableResult
    func createDemoSession() -> UUID {
        createSession(title: DemoContent.title,
                      source: SourceInfo(kind: .demo, name: "\(DemoContent.pdfName).pdf"),
                      isDemo: true)
    }

    /// Copies an imported PDF into the app sandbox so the session keeps working offline.
    func importPDF(from url: URL) throws -> UUID {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let fileName = UUID().uuidString + ".pdf"
        try FileManager.default.copyItem(at: url, to: SessionStore.sourcesDirectory.appending(path: fileName))
        let title = url.deletingPathExtension().lastPathComponent
        return createSession(title: title, source: SourceInfo(kind: .pdf, name: url.lastPathComponent, fileName: fileName))
    }

    func sourceURL(for session: StudySession) -> URL? {
        switch session.source.kind {
        case .demo: Bundle.main.url(forResource: DemoContent.pdfName, withExtension: "pdf")
        case .pdf: session.source.fileName.map { SessionStore.sourcesDirectory.appending(path: $0) }
        default: nil
        }
    }
}
