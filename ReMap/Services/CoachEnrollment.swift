import Foundation
import StoreKit
import Security

/// Coalesces first-launch and on-demand access without asking the tester for credentials.
final class CoachEnrollment {
    static let shared = CoachEnrollment()
    private var pending: Task<String, Error>?
    private let enabled: () -> Bool
    private let cached: () -> String?
    private let proof: () async throws -> String
    private let installation: () throws -> String
    private let exchange: (Data) async throws -> Data
    private let save: (String, Date) -> Bool

    init(enabled: @escaping () -> Bool = { CoachConnection.endpoint?.absoluteString == CoachConnection.productionURL },
         cached: @escaping () -> String? = { CoachConnection.token },
         proof: @escaping () async throws -> String = { try await CoachEnrollment.appleProof() },
         installation: @escaping () throws -> String = { try CoachEnrollment.installationID() },
         exchange: @escaping (Data) async throws -> Data = { try await CoachGateway.enroll(body: $0) },
         save: @escaping (String, Date) -> Bool = { CoachConnection.saveToken($0, expiresAt: $1) }) {
        self.enabled = enabled; self.cached = cached; self.proof = proof
        self.installation = installation; self.exchange = exchange; self.save = save
    }

    func warmUp() async { _ = try? await ensureAccess() }

    func ensureAccess() async throws -> String {
        guard enabled() else { throw CoachGatewayError.access }
        if let token = cached() { return token }
        if let pending { return try await pending.value }
        let task = Task { [self] in
            struct Input: Encodable { let installationID: String; let appTransaction: String }
            struct Reply: Decodable { let token: String; let expiresAt: TimeInterval }
            let signed = try await proof()
            guard enabled() else { throw CoachGatewayError.access }
            let input = Input(installationID: try installation(), appTransaction: signed)
            let reply = try JSONDecoder().decode(Reply.self, from: await exchange(JSONEncoder().encode(input)))
            let expiry = Date(timeIntervalSince1970: reply.expiresAt)
            guard enabled(), reply.token.range(of: "^rm1_[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
                  expiry > Date().addingTimeInterval(60), expiry < Date().addingTimeInterval(31 * 86400),
                  save(reply.token, expiry) else { throw CoachGatewayError.access }
            return reply.token
        }
        pending = task
        defer { pending = nil }
        return try await task.value
    }

    private static func appleProof() async throws -> String {
        let result = try await AppTransaction.shared
        guard case .verified(let transaction) = result,
              transaction.bundleID == Bundle.main.bundleIdentifier,
              transaction.environment == .sandbox,
              transaction.revocationDate == nil else { throw CoachGatewayError.access }
        return result.jwsRepresentation
    }

    private static func installationID() throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.selimtatar.ReMap.coach", kSecAttrAccount as String: "installation",
            kSecReturnData as String: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8),
           value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil { return value }
        guard status == errSecItemNotFound else { throw CoachGatewayError.access }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CoachGatewayError.access }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        var add = query; add.removeValue(forKey: kSecReturnData as String)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw CoachGatewayError.access }
        return value
    }
}
