import Foundation

nonisolated struct CoverRequest: Codable, Equatable, Sendable {
    var id: UUID
    var sessionID: UUID
    var title: String
    var headlines: [String]
    var styleVersion = 1
}

nonisolated struct CoverReply: Codable, Sendable {
    var id: UUID
    var status: String
    var imageURL: URL?
    var error: String?
}

nonisolated protocol CoverServing: Sendable {
    func submit(_ request: CoverRequest) async throws -> CoverReply
    func status(_ id: UUID) async throws -> CoverReply
    func download(_ url: URL) async throws -> Data
}

nonisolated enum CoverServiceError: Error {
    case unavailable, unauthorized, limited, invalidImage
}

private final class CoverNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest,
                               completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The app only calls ReMap's bounded cover routes. The fal key never reaches the iPad.
nonisolated struct CoverService: CoverServing {
    let endpoint: URL
    let token: String

    func submit(_ request: CoverRequest) async throws -> CoverReply {
        try await send(path: "covers", body: JSONEncoder().encode(request))
    }

    func status(_ id: UUID) async throws -> CoverReply {
        try await send(path: "covers/\(id.uuidString.lowercased())", body: nil)
    }

    private func send(path: String, body: Data?) async throws -> CoverReply {
        var request = URLRequest(url: endpoint.appending(path: path), timeoutInterval: 25)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-ReMap-Token")
        let session = URLSession(configuration: .ephemeral, delegate: CoverNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 16_384 else { throw CoverServiceError.unavailable }
        if http.statusCode == 401 { throw CoverServiceError.unauthorized }
        if http.statusCode == 429 { throw CoverServiceError.limited }
        guard (200...299).contains(http.statusCode) else { throw CoverServiceError.unavailable }
        return try JSONDecoder().decode(CoverReply.self, from: data)
    }

    func download(_ url: URL) async throws -> Data {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host,
              host.hasSuffix(".fal.media") || host == "fal.media" || host == "storage.googleapis.com"
        else { throw CoverServiceError.invalidImage }
        // No credentials, cookies or redirects are sent to image hosts.
        let session = URLSession(configuration: .ephemeral, delegate: CoverNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (file, response) = try await session.download(for: URLRequest(url: url, timeoutInterval: 40))
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType?.hasPrefix("image/") == true,
              response.expectedContentLength <= 12_000_000 else { throw CoverServiceError.invalidImage }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 12_000_000 else { throw CoverServiceError.invalidImage }
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }
}
