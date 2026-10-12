import Foundation
import Observation

/// Owns all study sessions and persists them as JSON in Application Support.
/// The JSON shape is the data contract we'll share with the web client and the backend.
@Observable
final class SessionStore {
    private(set) var sessions: [StudySession] = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    @ObservationIgnored private let fileURL: URL
    private static var defaultFileURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "ReMap", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "sessions.json")
    }

    static var sourcesDirectory: URL {
        let dir = URL.documentsDirectory.appending(path: "Sources", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init(preview: [StudySession]? = nil, fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        if let preview { sessions = preview; return }
        load()
    }

    var sortedSessions: [StudySession] { sessions.sorted { $0.updatedAt > $1.updatedAt } }

    func session(_ id: UUID) -> StudySession? { sessions.first { $0.id == id } }

    func add(_ session: StudySession) {
        sessions.append(session)
        scheduleSave()
    }

    func update(_ session: StudySession) {
        guard let i = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var s = session
        s.updatedAt = Date()
        sessions[i] = s
        scheduleSave()
    }

    func delete(_ id: UUID) {
        if let fileName = session(id)?.source.fileName {
            try? FileManager.default.removeItem(at: Self.sourcesDirectory.appending(path: fileName))
        }
        sessions.removeAll { $0.id == id }
        scheduleSave()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            sessions = try JSONDecoder.remap.decode([StudySession].self, from: data)
        } catch {
            // Keep the unreadable file for inspection instead of silently overwriting it.
            try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupt"))
        }
    }

    /// Debounced so rapid edits (dragging nodes) don't hammer the disk.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let data = try? JSONEncoder.remap.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

nonisolated extension JSONEncoder {
    static var remap: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

nonisolated extension JSONDecoder {
    static var remap: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
