import Testing
import Foundation
import UIKit
@testable import ReMap

private actor TestCoverService: CoverServing {
    var requests: [CoverRequest] = []
    var failDownload: Bool
    let data: Data
    var heldDownload: CheckedContinuation<Data, Never>?
    var hold = false
    let replyStatus: String

    init(data: Data, failDownload: Bool = false, hold: Bool = false, replyStatus: String = "ready") {
        self.data = data
        self.failDownload = failDownload
        self.hold = hold
        self.replyStatus = replyStatus
    }

    func submit(_ request: CoverRequest) async throws -> CoverReply {
        requests.append(request)
        return CoverReply(id: request.id, status: replyStatus, imageURL: URL(string: "https://v3.fal.media/cover.png"))
    }

    func status(_ id: UUID) async throws -> CoverReply {
        CoverReply(id: id, status: "ready", imageURL: URL(string: "https://v3.fal.media/cover.png"))
    }

    func download(_ url: URL) async throws -> Data {
        if hold { return await withCheckedContinuation { heldDownload = $0 } }
        if failDownload { throw URLError(.notConnectedToInternet) }
        return data
    }

    func restoreConnection() { failDownload = false }
    func releaseDownload() { heldDownload?.resume(returning: data); heldDownload = nil }
    func downloadStarted() -> Bool { heldDownload != nil }
}

@MainActor
@Suite("Library covers")
struct CoverTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "remap-covers-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func topic(_ title: String = "Endocrine basics") -> StudySession {
        StudySession(title: title, source: SourceInfo(kind: .text, name: "Private source", text: "Never send this full text"), map: MindMap(title: title))
    }

    private func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).pngData { context in
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
    }

    private func wait(until condition: () async -> Bool) async throws {
        for _ in 0..<150 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Cover operation did not complete")
    }

    @Test("Ready images persist and do not alter study timestamps or content")
    func persistence() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = TestCoverService(data: png())
        let store = CoverStore(directory: dir, service: service)
        let session = topic()
        let original = session
        store.synchronize([session], enabled: true)
        try await wait { store.records[session.id]?.state == .ready }
        #expect(store.image(for: session.id) != nil)
        #expect(session == original)
        let restored = CoverStore(directory: dir, service: service)
        restored.synchronize([session], enabled: true)
        #expect(restored.image(for: session.id) != nil)
        #expect(await service.requests.count == 1)
    }

    @Test("Download interruption resumes the same paid attempt after restart")
    func restart() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = TestCoverService(data: png(), failDownload: true)
        let session = topic()
        let first = CoverStore(directory: dir, service: service)
        first.synchronize([session], enabled: true)
        try await wait { first.records[session.id]?.state == .waiting }
        let id = first.records[session.id]?.request.id
        first.pause()
        await service.restoreConnection()
        let restored = CoverStore(directory: dir, service: service)
        restored.synchronize([session], enabled: true)
        try await wait { restored.records[session.id]?.state == .ready }
        #expect(restored.records[session.id]?.request.id == id)
        #expect(Set(await service.requests.map(\.id)).count == 1)
    }

    @Test("Retry after lost connection preserves the idempotency key")
    func retry() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = TestCoverService(data: png(), failDownload: true)
        let session = topic()
        let store = CoverStore(directory: dir, service: service)
        store.synchronize([session], enabled: true)
        try await wait { store.records[session.id]?.state == .waiting }
        let id = store.records[session.id]?.request.id
        await service.restoreConnection()
        store.refresh(session)
        try await wait { store.records[session.id]?.state == .ready }
        #expect(store.records[session.id]?.request.id == id)
    }

    @Test("Deleting a topic rejects a late generation result")
    func deletion() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = TestCoverService(data: png(), hold: true)
        let store = CoverStore(directory: dir, service: service)
        let session = topic()
        store.synchronize([session], enabled: true)
        try await wait { await service.downloadStarted() }
        store.remove(session.id)
        await service.releaseDownload()
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.records[session.id] == nil)
        #expect(store.image(for: session.id) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".png") }.isEmpty)
    }

    @Test("Rename and repeated appearances keep an existing cover")
    func rename() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = TestCoverService(data: png())
        let store = CoverStore(directory: dir, service: service)
        var session = topic()
        store.synchronize([session], enabled: true)
        try await wait { store.records[session.id]?.state == .ready }
        session.title = "Renamed"
        for _ in 0..<10 { store.synchronize([session], enabled: true) }
        #expect(await service.requests.count == 1)
        store.refresh(session)
        try await wait { await service.requests.count == 2 }
        #expect(Set(await service.requests.map(\.id)).count == 2)
        try await wait { store.records[session.id]?.state == .ready }
    }

    @Test("Disabled generation spends nothing and preserves readable placeholders")
    func disabled() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = TestCoverService(data: png())
        let store = CoverStore(directory: dir, service: service)
        let session = topic()
        store.synchronize([session], enabled: false)
        #expect(await service.requests.isEmpty)
        #expect(!store.isWorking(session.id))
        #expect(store.records[session.id] != nil)
    }

    @Test("Backfill is sequential, most recent first, with bounded context")
    func backfill() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = TestCoverService(data: png())
        let store = CoverStore(directory: dir, service: service)
        var older = topic("History"), newer = topic("Economics")
        older.updatedAt = Date(timeIntervalSince1970: 1)
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        newer.headlines = (0..<12).map { Headline(text: "Heading \($0)") }
        store.synchronize([older, newer], enabled: true)
        try await wait { store.records[older.id]?.state == .ready }
        let sent = await service.requests
        #expect(sent.map(\.sessionID) == [newer.id, older.id])
        #expect(sent[0].headlines.count == 6)
        #expect(!String(data: try JSONEncoder().encode(sent), encoding: .utf8)!.contains("Never send"))
    }

    @Test("Adaptive layout and paper identities stay stable")
    func layout() {
        #expect(LibraryPaperStyle.columnCount(width: 350) == 1)
        #expect(LibraryPaperStyle.columnCount(width: 740) == 2)
        #expect(LibraryPaperStyle.columnCount(width: 1100) == 3)
        #expect(LibraryPaperStyle.columnCount(width: 1500) == 3)
        #expect(LibraryPaperStyle.columnCount(width: 952, isPortrait: true) == 2)
        #expect(LibraryPaperStyle.columnCount(width: 350, isPortrait: true) == 1)
        let id = UUID()
        #expect(LibraryPaperStyle.seed(id) == LibraryPaperStyle.seed(id))
    }

    @Test("Unreadable paid-attempt history cannot trigger fresh automatic generations")
    func damagedIndex() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = Data("damaged index".utf8)
        let index = dir.appending(path: "index.json")
        try original.write(to: index)
        let service = TestCoverService(data: png())
        let store = CoverStore(directory: dir, service: service)
        store.synchronize([topic()], enabled: true)
        #expect(await service.requests.isEmpty)
        #expect(try Data(contentsOf: index) == original)
    }

    @Test("A failed disk write prevents paid submission")
    func unwritableIndex() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let notADirectory = dir.appending(path: "file")
        try Data("x".utf8).write(to: notADirectory)
        let service = TestCoverService(data: png())
        let store = CoverStore(directory: notADirectory, service: service)
        store.synchronize([topic()], enabled: true)
        #expect(await service.requests.isEmpty)
    }

    @Test("Closing during an in-flight response resumes one attempt and ignores canceled work")
    func pendingRestart() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let firstService = TestCoverService(data: png(), hold: true)
        let session = topic()
        let first = CoverStore(directory: dir, service: firstService)
        first.synchronize([session], enabled: true)
        try await wait { await firstService.downloadStarted() }
        let attempt = first.records[session.id]?.request.id
        first.pause()
        let secondService = TestCoverService(data: png())
        let restored = CoverStore(directory: dir, service: secondService)
        restored.synchronize([session], enabled: true)
        try await wait { restored.records[session.id]?.state == .ready }
        await firstService.releaseDownload()
        try await Task.sleep(for: .milliseconds(30))
        let reopened = CoverStore(directory: dir, service: secondService)
        #expect(reopened.records[session.id]?.request.id == attempt)
        #expect(reopened.records[session.id]?.state == .ready)
        #expect(reopened.image(for: session.id) != nil)
        let requests = await firstService.requests + secondService.requests
        #expect(Set(requests.map(\.id)).count == 1)
    }

    @Test("Failed, uncertain and capped attempts keep usable placeholders without automatic spending",
          arguments: ["failed", "limited", "uncertain"])
    func terminalStates(_ state: String) async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = TestCoverService(data: png(), replyStatus: state)
        let store = CoverStore(directory: dir, service: service)
        let session = topic()
        store.synchronize([session], enabled: true)
        try await wait { store.records[session.id]?.state.rawValue == state }
        for _ in 0..<5 { store.synchronize([session], enabled: true) }
        #expect(await service.requests.count == 1)
        #expect(store.image(for: session.id) == nil)
        #expect(!store.isWorking(session.id))
        if state == "uncertain" {
            let attempt = store.records[session.id]?.request.id
            store.refresh(session)
            try await wait { await service.requests.count == 2 }
            #expect(store.records[session.id]?.request.id == attempt)
        }
    }
}
