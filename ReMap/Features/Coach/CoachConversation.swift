import Foundation
import Observation

nonisolated enum CoachPresentation: Equatable { case collapsed, chat, voice }
nonisolated enum CoachActivity: Equatable { case idle, connecting, listening, thinking, speaking, muted, unavailable }

/// One conversation history and one audio connection per study session.
@Observable
final class CoachConversation {
    var presentation: CoachPresentation = .collapsed
    var draft = ""
    private(set) var isMicrophoneMuted = false
    private(set) var lastActionSummary: String?
    @ObservationIgnored private weak var model: SessionModel?
    private var realtime: RealtimeVoiceSession
    @ObservationIgnored private let cloudAvailable: () -> Bool
    @ObservationIgnored private let requestText: (Data) async throws -> Data
    private var requestingText = false
    private var localError: String?
    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var voiceTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var appliedCalls: Set<String> = []
    @ObservationIgnored private var lastActionMap: MindMap?
    @ObservationIgnored private var latestUserRequest = ""
    @ObservationIgnored private var receivingVoice = false
    @ObservationIgnored private var voiceAttemptActive = false
    @ObservationIgnored private var contextRevision: UUID?
    @ObservationIgnored private var contextReviewMode: CoachSession.Mode?

    init(model: SessionModel, realtime: RealtimeVoiceSession = RealtimeVoiceSession(),
         cloudAvailable: @escaping () -> Bool = { CoachConnection.endpoint != nil },
         requestText: @escaping (Data) async throws -> Data = { try await CoachGateway.post(path: "coach", body: $0) }) {
        self.model = model; self.realtime = realtime; self.cloudAvailable = cloudAvailable
        self.requestText = requestText
    }

    var activity: CoachActivity {
        if voiceError != nil { return .unavailable }
        if presentation == .voice {
            if !realtime.isConnected { return .connecting }
            switch realtime.state {
            case .speaking: return .speaking
            case .thinking: return .thinking
            case .unavailable: return .unavailable
            default: return isMicrophoneMuted ? .muted : .listening
            }
        }
        return requestingText || model?.coach.isThinking == true ? .thinking : .idle
    }
    var audioLevel: Double { realtime.level }
    var caption: String { realtime.assistantTranscript }
    var userTranscript: String { realtime.transcript }
    var voiceError: String? {
        if let localError { return localError }
        if case .unavailable(let reason) = realtime.state { return reason }
        return nil
    }
    var voiceProviderLabel: String { "OpenAI Realtime · AI voice" }
    var canUndoLastAction: Bool { lastActionMap != nil && model?.map == lastActionMap && model?.canUndo == true }

    func openChat() {
        if presentation == .voice { stopVoice() }
        presentation = .chat
        model?.coach.open()
    }

    func close() {
        generation = UUID(); requestTask?.cancel(); voiceTask?.cancel()
        requestingText = false; realtime.shutDown(); isMicrophoneMuted = false
        voiceAttemptActive = false
        presentation = .collapsed; model?.coach.close(); model?.isVoiceOpen = false
    }

    func send(_ text: String) {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !clean.isEmpty, let model else { return }
        draft = ""; localError = nil; latestUserRequest = clean
        if presentation == .collapsed { presentation = .chat }
        requestTask?.cancel(); requestingText = false
        if handlesReviewReply(clean) { model.coach.reply(clean); return }
        appendUser(clean)
        if presentation == .voice, realtime.isConnected {
            realtime.respond(context: context(for: clean)); return
        }
        guard cloudAvailable() else {
            model.coach.say(String(localized: "The cloud connection is unavailable. Your map is saved, and Check my map can still review its structure offline."), replies: [String(localized: "Check my map")])
            return
        }
        let input = context(for: clean)
        let id = UUID(); generation = id
        requestingText = true
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == id { requestingText = false } }
            do {
                struct Request: Encodable { let operation = "conversation"; let context: String }
                struct Reply: Decodable { let message: String; let command: CoachMapCommand?; let review_answer: String? }
                let body = try JSONEncoder().encode(Request(context: input))
                let data = try await requestText(body)
                let reply = try JSONDecoder().decode(Reply.self, from: data)
                guard !Task.isCancelled, generation == id else { return }
                // Publish completion before the animated message update so the visible
                // answer and its enabled controls share the same finished state.
                requestingText = false
                if let answer = reply.review_answer {
                    let result = submitReviewAnswer(answer)
                    if !result.ok { model.coach.say(result.message) }
                } else if let command = reply.command {
                    let result = execute(command, callID: id.uuidString, latestRequest: latestUserRequest)
                    model.coach.say(result.message)
                } else { model.coach.say(reply.message) }
            } catch {
                guard !Task.isCancelled, generation == id else { return }
                requestingText = false
                model.coach.say((error as? CoachGatewayError)?.localizedDescription ?? String(localized: "The cloud coach could not reply. Your map is saved; try again or use Check my map for an offline review."))
            }
        }
    }

    func waitForPendingReply() async { await requestTask?.value }

    /// A new study phase invalidates its old reply, while keeping the live call.
    func prepareForPhaseChange() {
        generation = UUID(); requestTask?.cancel(); requestingText = false
        contextRevision = nil; contextReviewMode = nil
        if presentation == .voice { realtime.interrupt() }
    }

    func startVoice() async {
        guard !voiceAttemptActive else { return }
        voiceAttemptActive = true
        requestTask?.cancel(); requestingText = false
        localError = nil; presentation = .voice; model?.isVoiceOpen = false
        guard cloudAvailable() else {
            localError = String(localized: "Voice could not connect to the cloud coach. Return to chat to continue with an offline map review, or retry when the connection is ready.")
            return
        }
        isMicrophoneMuted = false
        realtime.onAnswer = { [weak self] text in self?.send(text) }
        realtime.onBargeIn = { [weak self] in
            self?.requestTask?.cancel(); self?.requestingText = false
        }
        realtime.onAssistantText = { [weak self] text in
            guard let self, !text.isEmpty else { return }
            receivingVoice = true
            model?.coach.say(text)
            receivingVoice = false
        }
        realtime.onInterrupted = { [weak self] in
            guard let coach = self?.model?.coach else { return }
            // Realtime gives no word timestamps: never invent a "heard" text prefix.
            coach.messages.append(.init(text: String(localized: "Voice reply interrupted before completion.")))
        }
        realtime.onReviewAnswer = { [weak self] data, callID in
            struct Answer: Decodable { let answer: String }
            guard let self, !appliedCalls.contains(callID),
                  let answer = try? JSONDecoder().decode(Answer.self, from: data) else {
                return "{\"ok\":false,\"message\":\"Invalid or repeated review answer.\"}"
            }
            appliedCalls.insert(callID)
            let result = submitReviewAnswer(answer.answer)
            return String(data: (try? JSONEncoder().encode(result)) ?? Data(), encoding: .utf8) ?? "{}"
        }
        realtime.onCommand = { [weak self] data, callID in
            guard let self, let command = try? JSONDecoder().decode(CoachMapCommand.self, from: data) else {
                return "{\"ok\":false,\"message\":\"Invalid map command; nothing changed.\"}"
            }
            let result = execute(command, callID: callID, latestRequest: latestUserRequest)
            let body = (try? JSONEncoder().encode(result)) ?? Data()
            return String(data: body, encoding: .utf8) ?? "{}"
        }
        await realtime.connect(conversation: true)
    }

    func stopVoice() {
        voiceTask?.cancel(); realtime.shutDown(); isMicrophoneMuted = false
        voiceAttemptActive = false
        localError = nil; presentation = .chat; model?.isVoiceOpen = false
    }
    func toggleMicrophone() {
        guard presentation == .voice, realtime.isConnected else { return }
        isMicrophoneMuted.toggle(); realtime.setMicrophoneMuted(isMicrophoneMuted)
    }
    func retryVoice() async { stopVoice(); await startVoice() }
    /// UI calls this only when actually backgrounded, not during a permission dialog.
    func sceneBecameInactive() { if presentation == .voice { stopVoice() } }
    func undoLastAction() {
        guard canUndoLastAction else { return }
        model?.undo(); lastActionMap = nil; lastActionSummary = String(localized: "Undid the coach's last map change.")
    }

    func didReceiveCoachMessage(_ text: String) {
        guard presentation == .voice, !receivingVoice else { return }
        realtime.speak(text)
    }

    private func handlesReviewReply(_ text: String) -> Bool {
        guard let coach = model?.coach else { return false }
        if coach.replies.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) { return true }
        if text.caseInsensitiveCompare(String(localized: "Check my map")) == .orderedSame { return true }
        switch coach.mode {
        // A connected conversation decides whether free text answers the active review.
        // This keeps unrelated questions and edit requests available during placement.
        case .placing: return CoachConnection.endpoint == nil
        case .grouping: return CoachConnection.endpoint == nil && text.split(whereSeparator: \.isWhitespace).count <= 3
        default: return false
        }
    }
    private func appendUser(_ text: String) {
        guard let coach = model?.coach else { return }
        coach.messages.append(.init(text: text, fromUser: true))
    }
    private func context(for text: String) -> String {
        guard let model else { return "{}" }
        struct Entry: Encodable { let role: String; let text: String }
        struct Review: Encodable { let mode: String; let question: String }
        struct Context: Encodable { let message: String; let history: [Entry]; let map: CoachBoardSnapshot; let review: Review? }
        let reviewMode: String?
        switch model.coach.mode {
        case .placing: reviewMode = "placing"
        case .grouping: reviewMode = "grouping"
        case .reviewing: reviewMode = model.coach.current == nil ? nil : "reviewing"
        default: reviewMode = nil
        }
        contextRevision = model.mapRevision; contextReviewMode = model.coach.mode
        let review = reviewMode.map { Review(mode: $0, question: String((model.coach.latestCoachMessage?.text ?? "").prefix(1000))) }
        var history = model.coach.messages.dropLast().suffix(10).map { Entry(role: $0.fromUser ? "user" : "assistant", text: String($0.text.prefix(1000))) }
        var snapshot = model.coachSnapshot
        while true {
            let data = (try? JSONEncoder().encode(Context(message: text, history: history, map: snapshot, review: review))) ?? Data()
            if data.count <= 20000 { return String(data: data, encoding: .utf8) ?? "{}" }
            if !history.isEmpty { history.removeFirst(); continue }
            guard !snapshot.nodes.isEmpty else { return "{}" }
            let nodes = Array(snapshot.nodes.dropLast())
            let ids = Set(nodes.map(\.id))
            snapshot = CoachBoardSnapshot(revision: snapshot.revision, title: snapshot.title, nodes: nodes,
                edges: snapshot.edges.filter { ids.contains($0.from) && ids.contains($0.to) },
                selectedNode: snapshot.selectedNode.flatMap { ids.contains($0) ? $0 : nil },
                selectedEdge: snapshot.selectedEdge, truncated: true,
                phase: snapshot.phase, canUndo: snapshot.canUndo, findings: snapshot.findings)
        }
    }
    struct ActionResult: Encodable { let ok: Bool; let message: String }
    private func submitReviewAnswer(_ answer: String) -> ActionResult {
        guard let model, answer == latestUserRequest, model.mapRevision == contextRevision,
              model.coach.mode == contextReviewMode, model.coach.mode != .idle,
              model.coach.mode != .finished else {
            return .init(ok: false, message: "The review changed while I was thinking. Please answer the current question again.")
        }
        // The common history already contains this student turn; CoachSession appends it.
        if model.coach.messages.last?.fromUser == true, model.coach.messages.last?.text == answer {
            model.coach.messages.removeLast()
        }
        model.coach.reply(answer)
        return .init(ok: true, message: "The answer was submitted to the active review for validation.")
    }
    func execute(_ command: CoachMapCommand, callID: String, latestRequest: String) -> ActionResult {
        guard let model else { return .init(ok: false, message: "Session closed.") }
        guard !appliedCalls.contains(callID) else { return .init(ok: false, message: "This command was already handled; no duplicate edit.") }
        appliedCalls.insert(callID)
        do {
            let previous = model.map
            let message = try model.applyCoachCommand(command, latestRequest: latestRequest)
            if command.operations.contains(where: { $0.kind == .undo }) { lastActionMap = nil }
            else if model.map != previous { lastActionMap = model.map }
            else { lastActionMap = nil }
            lastActionSummary = message
            return .init(ok: true, message: message)
        } catch { return .init(ok: false, message: error.localizedDescription) }
    }
}
