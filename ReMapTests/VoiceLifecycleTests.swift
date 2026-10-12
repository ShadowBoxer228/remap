import Foundation
import Testing
@testable import ReMap

@MainActor
@Suite("Voice connection lifecycle", .timeLimit(.minutes(1)))
struct VoiceLifecycleTests {
    private func model() -> SessionModel {
        let session = StudySession(title: "Voice test", source: SourceInfo(kind: .text, name: "Fixture"), map: MindMap(title: "Voice test"))
        let store = SessionStore(preview: [session], fileURL: FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID()).json"))
        let model = SessionModel(session: session, store: store, ingestor: LocalSourceIngestor())
        model.coach.brain = TemplateBrain()
        return model
    }

    @Test("Denied microphone permission never requests a paid voice token")
    func deniedPermission() async {
        var tokens = 0
        let voice = RealtimeVoiceSession(requestPermission: { false }, fetchToken: { _ in tokens += 1; return Data() })
        await voice.connect(conversation: true)
        #expect(tokens == 0)
        if case .unavailable = voice.state {} else { Issue.record("Denied permission must be explicit") }
        #expect(!voice.isConnected && !voice.isMicrophoneActive)
    }

    @Test("Token connection failure leaves no running microphone or connection")
    func failedConnection() async {
        var tokens = 0
        let voice = RealtimeVoiceSession(requestPermission: { true }, fetchToken: { _ in tokens += 1; throw CoachGatewayError.limit })
        await voice.connect(conversation: true)
        #expect(tokens == 1)
        if case .unavailable(let reason) = voice.state { #expect(reason.contains("limit")) }
        else { Issue.record("Quota failure must be explicit") }
        #expect(!voice.isConnected && !voice.isMicrophoneActive)
        voice.shutDown()
        #expect(voice.state == .idle)
    }

    @Test("Shutdown ignores a microphone permission answer arriving later")
    func latePermission() async {
        let permission = SuspendedVoiceValue<Bool>()
        var tokens = 0
        let voice = RealtimeVoiceSession(requestPermission: { await permission.value() }, fetchToken: { _ in tokens += 1; return Data() })
        let start = Task { await voice.connect(conversation: true) }
        await permission.waitForRequest()
        voice.shutDown()
        permission.resume(true)
        await start.value
        #expect(tokens == 0)
        #expect(voice.state == .idle)
        #expect(!voice.isConnected && !voice.isMicrophoneActive)
    }

    @Test("Closing chat while token creation is pending cannot start voice later")
    func lateTokenAfterClose() async {
        let token = SuspendedVoiceValue<Data>()
        let voice = RealtimeVoiceSession(requestPermission: { true }, fetchToken: { _ in await token.value() })
        let model = model()
        let conversation = CoachConversation(model: model, realtime: voice, cloudAvailable: { true })
        conversation.draft = "Keep my draft"
        let start = Task { await conversation.startVoice() }
        await token.waitForRequest()
        conversation.close()
        token.resume(Data("{\"value\":\"ek_fixture\",\"expires_at\":9999999999,\"model\":\"gpt-realtime-2.1\"}".utf8))
        await start.value
        #expect(conversation.presentation == .collapsed)
        #expect(conversation.draft == "Keep my draft")
        #expect(voice.state == .idle)
        #expect(!voice.isConnected && !voice.isMicrophoneActive)
    }

    @Test("Duplicate start and background during permission do not create another session")
    func duplicateAndBackground() async {
        let permission = SuspendedVoiceValue<Bool>()
        var requests = 0, tokens = 0
        let voice = RealtimeVoiceSession(requestPermission: { requests += 1; return await permission.value() }, fetchToken: { _ in tokens += 1; return Data() })
        let model = model()
        let conversation = CoachConversation(model: model, realtime: voice, cloudAvailable: { true })
        let start = Task { await conversation.startVoice() }
        await permission.waitForRequest()
        await conversation.startVoice()
        #expect(requests == 1)
        conversation.sceneBecameInactive()
        permission.resume(true)
        await start.value
        #expect(tokens == 0)
        #expect(conversation.presentation == .chat)
        #expect(!voice.isConnected && !voice.isMicrophoneActive)
    }
    @Test("Late events from a closed connection cannot reconnect or publish captions")
    func staleConnectionEvents() throws {
        let voice = RealtimeVoiceSession(requestPermission: { false }, fetchToken: { _ in Data() })
        let oldConnection = voice.connectionIdentifier
        func event(_ body: [String: Any]) throws {
            voice.processServerEvent(try JSONSerialization.data(withJSONObject: body), connectionID: oldConnection)
        }
        try event(["type": "session.created"])
        #expect(voice.isConnected)
        voice.shutDown()
        try event(["type": "session.created"])
        try event(["type": "error", "error": ["code": "stale_error"]])
        try event(["type": "response.output_audio_transcript.delta", "response_id": "old", "delta": "Unheard words"])
        #expect(!voice.isConnected && !voice.isMicrophoneActive)
        #expect(voice.state == .idle)
        #expect(voice.assistantTranscript.isEmpty)
    }

    @Test("Interrupted response events cannot resume old audio or contaminate a later turn")
    func staleResponseEvents() throws {
        let voice = RealtimeVoiceSession(requestPermission: { false }, fetchToken: { _ in Data() })
        let connection = voice.connectionIdentifier
        func event(_ body: [String: Any]) throws {
            voice.processServerEvent(try JSONSerialization.data(withJSONObject: body), connectionID: connection)
        }
        try event(["type": "session.created"])
        voice.speak("A scripted response")
        let oldTurn = voice.responseTurnIdentifier.uuidString
        try event(["type": "response.created", "response": ["id": "response-old", "metadata": ["turn": oldTurn]]])
        voice.interrupt()
        try event(["type": "response.output_audio_transcript.delta", "response_id": "response-old", "delta": "Unheard words"])
        try event(["type": "response.output_audio.delta", "response_id": "response-old", "delta": Data(repeating: 0, count: 4800).base64EncodedString()])
        try event(["type": "response.done", "response": ["id": "response-old", "status": "failed"]])
        #expect(voice.assistantTranscript.isEmpty)
        #expect(voice.state == .idle)
        #expect(!voice.isMicrophoneActive)
        voice.shutDown()
    }

    @Test("A completed or failed text reply clears Thinking before publishing its message")
    func textCompletion() async {
        let token = SuspendedVoiceValue<Data>()
        let model = model()
        let conversation = CoachConversation(model: model, cloudAvailable: { true }, requestText: { _ in await token.value() })
        conversation.send("Explain this topic")
        await token.waitForRequest()
        #expect(conversation.activity == .thinking)
        token.resume(Data("{\"message\":\"Here is the explanation.\",\"command\":null}".utf8))
        await conversation.waitForPendingReply()
        #expect(conversation.activity == .idle)
        #expect(model.coach.messages.last?.text == "Here is the explanation.")
        let failing = CoachConversation(model: model, cloudAvailable: { true }, requestText: { _ in throw CoachGatewayError.limit })
        failing.send("Try another question")
        await failing.waitForPendingReply()
        #expect(failing.activity == .idle)
        #expect(model.coach.messages.last?.text.contains("limit") == true)
    }

    @Test("Full current-session history stays visible while only bounded context is sent")
    func fullHistoryBoundedContext() async throws {
        let model = model()
        for index in 0..<60 { model.coach.say("Earlier message \(index)") }
        let first = model.coach.messages.first
        let conversation = CoachConversation(model: model, cloudAvailable: { true }, requestText: { body in
            let request = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let encoded = try #require(request["context"] as? String)
            let context = try #require(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
            #expect((context["history"] as? [Any])?.count == 10)
            return Data("{\"message\":\"A new reply.\",\"command\":null}".utf8)
        })
        conversation.send("Continue")
        await conversation.waitForPendingReply()
        #expect(model.coach.messages.first == first)
        #expect(model.coach.messages.count == 62)
    }

}

@MainActor
private final class SuspendedVoiceValue<Value: Sendable> {
    private var requested = false
    private var continuation: CheckedContinuation<Value, Never>?
    func value() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            requested = true
        }
    }
    func waitForRequest() async {
        while !requested { await Task.yield() }
    }
    func resume(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
