import Foundation
import Observation
import UIKit
import ImageIO

nonisolated struct CoverRecord: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case queued, pending, waiting, ready, failed, uncertain, limited
    }
    var request: CoverRequest
    var state: State = .queued
    var fileName: String?
    var imageURL: URL?
    var error: String?
}

/// Cover changes never call SessionStore.update: map timestamps and JSON stay independent.
@Observable
final class CoverStore {
    static let enabledKey = "automaticTopicCovers"
    private(set) var records: [UUID: CoverRecord] = [:]
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let injectedService: (any CoverServing)?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var queue: [UUID] = []
    @ObservationIgnored private var runningID: UUID?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var readableIndex = true
    @ObservationIgnored private let images = NSCache<NSString, UIImage>()

    init(directory: URL? = nil, service: (any CoverServing)? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "ReMap/Covers", directoryHint: .isDirectory)
        self.injectedService = service
        images.countLimit = 12
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let index = self.directory.appending(path: "index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            do {
                let saved = try JSONDecoder().decode([CoverRecord].self, from: Data(contentsOf: index))
                for record in saved { records[record.request.sessionID] = record }
            } catch {
                // Preserve the file and stop automatic spending if paid-attempt history is unreadable.
                readableIndex = false
            }
        }
    }

    func image(for id: UUID) -> UIImage? {
        guard let name = records[id]?.fileName, name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        if let cached = images.object(forKey: name as NSString) { return cached }
        let url = directory.appending(path: name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 900,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        images.setObject(image, forKey: name as NSString)
        return image
    }

    func isWorking(_ id: UUID) -> Bool {
        guard enabled, readableIndex, service != nil, let state = records[id]?.state else { return false }
        return state == .queued || state == .pending
    }

    func synchronize(_ sessions: [StudySession], enabled: Bool) {
        self.enabled = enabled
        guard readableIndex else { return }
        let validIDs = Set(sessions.map(\.id))
        for id in Array(records.keys) where !validIDs.contains(id) { remove(id) }
        for session in sessions {
            if records[session.id] == nil {
                records[session.id] = CoverRecord(request: Self.request(for: session))
            }
            if let record = records[session.id], record.state == .ready,
               let file = record.fileName, !FileManager.default.fileExists(atPath: directory.appending(path: file).path) {
                records[session.id]?.state = .waiting
            }
        }
        guard persist() else { pause(); return }
        guard enabled else { pause(); return }
        for session in sessions.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard let state = records[session.id]?.state,
                  [.queued, .pending, .waiting].contains(state), runningID != session.id,
                  !queue.contains(session.id) else { continue }
            queue.append(session.id)
        }
        start()
    }

    func refresh(_ session: StudySession) {
        guard enabled, readableIndex else { return }
        if let state = records[session.id]?.state, [.uncertain, .waiting, .pending, .queued].contains(state) {
            // Reconcile this same paid attempt; never silently submit a replacement.
            records[session.id]?.state = .waiting
        } else {
            let oldFile = records[session.id]?.fileName
            records[session.id] = CoverRecord(request: Self.request(for: session), fileName: oldFile)
        }
        guard persist() else { return }
        if !queue.contains(session.id) { queue.append(session.id) }
        start()
    }

    func remove(_ id: UUID) {
        if let file = records[id]?.fileName { removeFile(file) }
        records.removeValue(forKey: id)
        queue.removeAll { $0 == id }
        persist()
    }

    func pause() {
        generation = UUID()
        worker?.cancel()
        worker = nil
        runningID = nil
        queue.removeAll()
        persist()
    }

    private static func request(for session: StudySession) -> CoverRequest {
        CoverRequest(id: UUID(), sessionID: session.id,
                     title: String(session.title.prefix(200)),
                     headlines: session.headlines.prefix(6).map { String($0.text.prefix(120)) })
    }

    private var service: (any CoverServing)? {
        if let injectedService { return injectedService }
        guard let raw = UserDefaults.standard.string(forKey: CoachConnection.endpointKey),
              let endpoint = CoachConnection.validatedURL(raw),
              let token = CoachConnection.token, !token.isEmpty else { return nil }
        return CoverService(endpoint: endpoint, token: token)
    }

    private func start() {
        guard worker == nil, enabled, readableIndex, let service else { return }
        let current = generation
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, current == self.generation, !self.queue.isEmpty {
                let id = self.queue.removeFirst()
                self.runningID = id
                await self.process(id, service: service)
            }
            guard current == self.generation else { return }
            self.runningID = nil
            self.worker = nil
        }
    }

    private func process(_ id: UUID, service: any CoverServing) async {
        guard let record = records[id] else { return }
        let attempt = record.request.id
        records[id]?.state = .pending
        // Never submit paid work unless its idempotency key is durably stored.
        guard persist() else { records[id]?.state = .waiting; return }
        do {
            var reply = try await service.submit(record.request)
            for _ in 0..<40 {
                try Task.checkCancellation()
                guard records[id]?.request.id == attempt else { return }
                guard reply.id == attempt else { throw CoverServiceError.unavailable }
                switch reply.status {
                case "ready":
                    guard let url = reply.imageURL else { throw CoverServiceError.invalidImage }
                    records[id]?.imageURL = url
                    persist()
                    let data = try await service.download(url)
                    try Task.checkCancellation()
                    guard records[id]?.request.id == attempt else { return }
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int,
                          let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, width <= 4096, height <= 4096 else { throw CoverServiceError.invalidImage }
                    let file = "\(id.uuidString)-\(attempt.uuidString).png"
                    try data.write(to: directory.appending(path: file), options: .atomic)
                    if let old = records[id]?.fileName, old != file { removeFile(old) }
                    records[id]?.fileName = file
                    records[id]?.state = .ready
                    records[id]?.error = nil
                    persist()
                    return
                case "failed", "uncertain", "limited":
                    records[id]?.state = CoverRecord.State(rawValue: reply.status) ?? .failed
                    records[id]?.error = reply.error
                    persist()
                    return
                default:
                    try await Task.sleep(for: .seconds(3))
                    reply = try await service.status(attempt)
                }
            }
            guard records[id]?.request.id == attempt else { return }
            records[id]?.state = .waiting
            persist()
        } catch {
            guard records[id]?.request.id == attempt, !Task.isCancelled else { return }
            switch error {
            case CoverServiceError.limited: records[id]?.state = .limited
            case CoverServiceError.invalidImage: records[id]?.state = .failed
            default: records[id]?.state = .waiting
            }
            persist()
        }
    }

    private func removeFile(_ file: String) {
        guard file == URL(fileURLWithPath: file).lastPathComponent else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: file))
        images.removeObject(forKey: file as NSString)
    }

    @discardableResult
    private func persist() -> Bool {
        guard readableIndex else { return false }
        do {
            let data = try JSONEncoder().encode(Array(records.values))
            try data.write(to: directory.appending(path: "index.json"), options: .atomic)
            return true
        } catch { return false }
    }
}
