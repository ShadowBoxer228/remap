import Foundation
import Security

/// Learning coach shares the automatically enrolled production connection.
enum LocalCoachConnection {
    static var endpoint: URL? { CoachConnection.endpoint }
    static var token: String? { CoachConnection.token }
}

private final class LocalCoachRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

enum LocalCoachGateway {
    static func post(path: String, body: Data, timeout: TimeInterval = 100, acceptedStatuses: Set<Int> = [200]) async throws -> Data {
        let route = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let endpoint = LocalCoachConnection.endpoint,
              !route.contains(".."), route.hasPrefix("api/") else { throw CoachGatewayError.access }
        let token = try await CoachEnrollment.shared.ensureAccess()
        do { return try await send(route: route, endpoint: endpoint, token: token, body: body, timeout: timeout, acceptedStatuses: acceptedStatuses) }
        catch CoachGatewayError.access {
            CoachConnection.invalidateToken(token)
            let refreshed = try await CoachEnrollment.shared.ensureAccess()
            return try await send(route: route, endpoint: endpoint, token: refreshed, body: body, timeout: timeout, acceptedStatuses: acceptedStatuses)
        }
    }

    private static func send(route: String, endpoint: URL, token: String, body: Data, timeout: TimeInterval, acceptedStatuses: Set<Int>) async throws -> Data {
        var request = URLRequest(url: endpoint.appendingPathComponent(route), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: LocalCoachRedirectGuard(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, data.count <= 8_000_000 else {
            throw LocalCoachFailure.message("The coach response could not be read. Your map is saved.")
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw CoachGatewayError.access }
        guard acceptedStatuses.contains(http.statusCode) else {
            struct Failure: Decodable { let error: String }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw LocalCoachFailure.message(failure?.error ?? "The coach connection failed (\(http.statusCode)). Your map is saved.")
        }
        return data
    }
}

nonisolated enum LocalCoachFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
