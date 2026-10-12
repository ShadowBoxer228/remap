import Foundation
import Security

/// Only the ReMap tester credential is stored on the iPad. Provider keys stay on the server.
enum CoachConnection {
    static let productionURL = "https://remap-coach.vercel.app"
    static let endpointKey = "coachEndpoint"
    static let enabledKey = "cloudCoachEnabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    private static let service = "com.selimtatar.ReMap.coach"

    static var endpoint: URL? {
        guard isEnabled else { return nil }
        let raw = UserDefaults.standard.string(forKey: endpointKey) ?? productionURL
        return validatedURL(raw)
    }

    static func validatedURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        return url
    }

    static var token: String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: "gateway",
                                   kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        if let credential = try? JSONDecoder().decode(Credential.self, from: data) {
            guard credential.endpoint == endpoint?.absoluteString,
                  credential.expiresAt.map({ $0 > Date().addingTimeInterval(60) }) ?? true else { return nil }
            return credential.token
        }
        // Compatibility for already provisioned internal DEBUG installations.
        return String(data: data, encoding: .utf8)
    }

    private struct Credential: Codable { let token: String; let endpoint: String; let expiresAt: Date? }

    static func saveToken(_ token: String, expiresAt: Date? = nil) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "gateway"]
        let target = UserDefaults.standard.string(forKey: endpointKey) ?? productionURL
        guard let data = try? JSONEncoder().encode(Credential(token: token, endpoint: target, expiresAt: expiresAt)) else { return false }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func invalidateToken(_ expected: String) {
        guard token == expected else { return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "gateway"] as CFDictionary)
    }
}

struct RemoteCoachBrain: CoachBrain {
    var fallback: any CoachBrain

    func question(for finding: Finding, in map: MindMap, isDemo: Bool) async -> String {
        if !isDemo, let response = try? await request(operation: "question", context: CoachPrompts.questionContext(finding: finding, map: map)),
           let text = response.question, let valid = CoachPrompts.validQuestion(text) {
            return valid
        }
        return await fallback.question(for: finding, in: map, isDemo: isDemo)
    }

    func judge(reason: String, label: String, parent: String) async -> Bool {
        if let response = try? await request(operation: "judge", context: CoachPrompts.judgeContext(reason: reason, label: label, parent: parent)),
           let grounded = response.grounded { return grounded }
        return await fallback.judge(reason: reason, label: label, parent: parent)
    }

    private func request(operation: String, context: String) async throws -> Reply {
        let data = try await CoachGateway.post(path: "coach", body: JSONEncoder().encode(Input(operation: operation, context: context)))
        return try JSONDecoder().decode(Reply.self, from: data)
    }

    private struct Input: Encodable { let operation: String; let context: String }
    private struct Reply: Decodable { let question: String?; let grounded: Bool? }
}

/// Credentials belong to the configured endpoint; never forward them through redirects.
private final class NoCoachRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest,
                               completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// A single private HTTPS gateway boundary for coach requests and temporary voice tokens.
nonisolated enum CoachGatewayError: LocalizedError {
    case access, limit, unavailable
    var errorDescription: String? {
        switch self {
        case .access: String(localized: "Cloud access could not be verified. Connect to the internet and try again. Your map remains available offline.")
        case .limit: String(localized: "The cloud coach is busy. Please try again in a minute. Your map remains available offline.")
        case .unavailable: String(localized: "The cloud coach is temporarily unavailable. Your map is saved; please try again later.")
        }
    }
}

enum CoachGateway {
    static func post(path: String, body: Data) async throws -> Data {
        guard !Task.isCancelled, let url = CoachConnection.endpoint else { throw CoachGatewayError.access }
        let token = try await CoachEnrollment.shared.ensureAccess()
        do { return try await send(path: path, body: body, url: url, token: token) }
        catch CoachGatewayError.access {
            // Unauthorized responses are rejected before any paid quota is reserved.
            CoachConnection.invalidateToken(token)
            let refreshed = try await CoachEnrollment.shared.ensureAccess()
            return try await send(path: path, body: body, url: url, token: refreshed)
        }
    }

    static func enroll(body: Data) async throws -> Data {
        guard let url = CoachConnection.endpoint, url.absoluteString == CoachConnection.productionURL else { throw CoachGatewayError.access }
        return try await send(path: "access/enroll", body: body, url: url, token: nil)
    }

    private static func send(path: String, body: Data, url: URL, token: String?) async throws -> Data {
        try Task.checkCancellation()
        guard CoachConnection.endpoint == url else { throw CoachGatewayError.access }
        var request = URLRequest(url: url.appending(path: path), timeoutInterval: 30)
        request.httpMethod = "POST"
        if let token { request.setValue(token, forHTTPHeaderField: "X-ReMap-Token") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let session = URLSession(configuration: .ephemeral, delegate: NoCoachRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, data.count <= 8192 else { throw CoachGatewayError.unavailable }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw CoachGatewayError.access
        case 429: throw CoachGatewayError.limit
        default: throw CoachGatewayError.unavailable
        }
        return data
    }
}
