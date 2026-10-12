import Foundation
import Testing
@testable import ReMap

@MainActor
@Suite("Automatic internal access")
struct CoachEnrollmentTests {
    private let credential = "rm1_" + String(repeating: "a", count: 43)
    private func reply(_ token: String, expiry: Date = Date().addingTimeInterval(86400)) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["token": token, "expiresAt": expiry.timeIntervalSince1970])
    }

    @Test("A fresh installation enrolls once and subsequent requests use its saved token")
    func freshInstall() async throws {
        var stored: String?, proofs = 0, exchanges = 0
        let response = try reply(credential)
        let enrollment = CoachEnrollment(enabled: { true }, cached: { stored }, proof: { proofs += 1; return "signed proof" },
            installation: { "installation" }, exchange: { data in
                exchanges += 1
                let input = try #require(JSONSerialization.jsonObject(with: data) as? [String: String])
                #expect(input == ["installationID":"installation", "appTransaction":"signed proof"])
                return response
            }, save: { token, _ in stored = token; return true })
        #expect(try await enrollment.ensureAccess() == credential)
        #expect(try await enrollment.ensureAccess() == credential)
        #expect(proofs == 1 && exchanges == 1)
    }

    @Test("Concurrent startup and coach requests share one registration")
    func concurrentRequests() async throws {
        var proofs = 0, exchanges = 0
        let response = try reply(credential)
        let enrollment = CoachEnrollment(enabled: { true }, cached: { nil }, proof: {
            proofs += 1; try await Task.sleep(for: .milliseconds(30)); return "proof"
        }, installation: { "installation" }, exchange: { _ in exchanges += 1; return response }, save: { _, _ in true })
        let first = Task { try await enrollment.ensureAccess() }
        let second = Task { try await enrollment.ensureAccess() }
        #expect(try await first.value == credential)
        #expect(try await second.value == credential)
        #expect(proofs == 1 && exchanges == 1)
    }

    @Test("An explicit opt-out makes no Apple or server request")
    func optOut() async {
        var touched = false
        let enrollment = CoachEnrollment(enabled: { false }, cached: { nil }, proof: { touched = true; return "proof" })
        await enrollment.warmUp()
        #expect(!touched)
    }

    @Test("Opt-out during registration cannot save a credential")
    func optOutDuringEnrollment() async throws {
        var enabled = true, saved = false
        let response = try reply(credential)
        let enrollment = CoachEnrollment(enabled: { enabled }, cached: { nil }, proof: { "proof" },
            installation: { "installation" }, exchange: { _ in enabled = false; return response }, save: { _, _ in saved = true; return true })
        await enrollment.warmUp()
        #expect(!saved)
    }

    @Test("A failed registration can retry without a stuck pending task")
    func retry() async throws {
        var count = 0
        let response = try reply(credential)
        let enrollment = CoachEnrollment(enabled: { true }, cached: { nil }, proof: {
            count += 1; if count == 1 { throw CoachGatewayError.unavailable }; return "proof"
        }, installation: { "installation" }, exchange: { _ in response }, save: { _, _ in true })
        await enrollment.warmUp()
        #expect(try await enrollment.ensureAccess() == credential)
        #expect(count == 2)
    }

    @Test("Expired or malformed server credentials are never saved")
    func invalidReply() async throws {
        for response in [try reply(credential, expiry: .distantPast), try reply("not-a-token"), try reply(credential, expiry: .distantFuture)] {
            var saved = false
            let enrollment = CoachEnrollment(enabled: { true }, cached: { nil }, proof: { "proof" }, installation: { "installation" },
                exchange: { _ in response }, save: { _, _ in saved = true; return true })
            await enrollment.warmUp()
            #expect(!saved)
        }
    }
}
