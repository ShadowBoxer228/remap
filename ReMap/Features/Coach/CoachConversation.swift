import Foundation
import Observation

nonisolated enum CoachPresentation: Equatable { case collapsed, chat, voice }
nonisolated enum CoachActivity: Equatable { case idle, connecting, listening, thinking, speaking, muted, unavailable }

/// One conversation history and one audio connection per study session.
@Observable
final class CoachConversation {
    var presentation: CoachPresentation = .collapsed
    var draft = ""
    var sourceReferences: [LocalCoachReference] = []
    var sourcePassages: [LocalSourceResult.Passage] = []
    var showingSource = false
    var selectedSourcePage = 1
    @ObservationIgnored private var failedLocalMessage: UUID?
    @ObservationIgnored private var failedLocalText: String?
    @ObservationIgnored private var localToolCalls: Set<String> = []
    private(set) var isMicrophoneMuted = false
    private(set) var lastActionSummary: String?
    @ObservationIgnored private weak var model: SessionModel?
    private var realtime: RealtimeVoiceSession
    @ObservationIgnored private let cloudAvailable: () -> Bool
    @ObservationIgnored private let requestText: (Data) async throws -> Data
    @ObservationIgnored private let requestPDFText: (Data) async throws -> Data
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
         requestText: @escaping (Data) async throws -> Data = { try await CoachGateway.post(path: "coach", body: $0) },
         requestPDFText: @escaping (Data) async throws -> Data = { try await LocalCoachGateway.post(path: "api/native/coach", body: $0) }) {
        self.model = model; self.realtime = realtime; self.cloudAvailable = cloudAvailable
        self.requestText = requestText
        self.requestPDFText = requestPDFText
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

    func send(_ text: String, fromVoice: Bool = false) {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !clean.isEmpty, let model else { return }
        draft = ""; localError = nil; latestUserRequest = clean
        sourceReferences = []; sourcePassages = []
        if presentation == .collapsed { presentation = .chat }
        requestTask?.cancel(); requestingText = false
        if handlesReviewReply(clean) { model.coach.reply(clean); return }
        if model.session.usesPDFCoach {
            sendLocal(clean, model: model, fromVoice: fromVoice); return
        }
        appendUser(clean)
        if presentation == .voice, realtime.isConnected {
            realtime.respond(context: context(for: clean), textInput: fromVoice ? nil : clean); return
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
        sourceReferences = []; sourcePassages = []; showingSource = false
        if presentation == .voice { realtime.interrupt() }
    }

    func startVoice() async {
        guard !voiceAttemptActive else { return }
        voiceAttemptActive = true
        requestTask?.cancel(); requestingText = false
        localError = nil; presentation = .voice; model?.isVoiceOpen = false
        let attempt = generation
        do { try await model?.prepareCoachSource() }
        catch {
            guard generation == attempt, !Task.isCancelled else { return }
            voiceAttemptActive = false; presentation = .chat; localError = error.localizedDescription
            model?.coach.say(error.localizedDescription)
            return
        }
        guard generation == attempt, !Task.isCancelled else { return }
        let voiceAvailable = model?.session.usesPDFCoach == true ? LocalCoachConnection.endpoint != nil : cloudAvailable()
        guard voiceAvailable else {
            voiceAttemptActive = false
            localError = model?.session.usesPDFCoach == true
                ? String(localized: "Enable Cloud coach in Library Settings to use voice.")
                : String(localized: "Voice could not connect to the cloud coach. Return to chat to continue with an offline map review, or retry when the connection is ready.")
            return
        }
        isMicrophoneMuted = false
        realtime.onAnswer = { [weak self] text in self?.send(text, fromVoice: true) }
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
        if let model, model.session.usesPDFCoach {
            realtime.localTokenBody = try? JSONEncoder().encode(model.localCoachRequest(message: "Start coaching in the learner’s language. Wait for their question.", includeSnapshot: false))
            realtime.onContext = { [weak self] in
                guard let self, let model = self.model else { return (text: "Session closed", images: []) }
                return model.localCoachContext(message: self.latestUserRequest)
            }
            realtime.onTool = { [weak self] name, data, callID in
                guard let self else { return NativeVoiceToolResult(output: "{\"error\":\"Session closed\"}", images: []) }
                return await self.localTool(name: name, arguments: data, callID: callID)
            }
        } else {
            realtime.localTokenBody = nil; realtime.onContext = nil; realtime.onTool = nil
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

    private func sendLocal(_ text: String, model: SessionModel, fromVoice: Bool) {
        // Failed messages are retryable without a duplicate user bubble.
        if let id = failedLocalMessage {
            model.coach.messages.removeAll { $0.id == id }
            failedLocalMessage = nil; failedLocalText = nil
        }
        model.coach.replies = []
        appendUser(text)
        let userID = model.coach.messages.last?.id
        contextRevision = model.mapRevision; contextReviewMode = model.coach.mode
        if presentation == .voice, realtime.isConnected {
            realtime.respond(context: "Respond to the latest learner request using the current map and source tools.", textInput: fromVoice ? nil : text)
            return
        }
        let id = UUID(); generation = id
        let originalRevision = model.mapRevision
        requestingText = true
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == id { requestingText = false } }
            do {
                try await model.prepareCoachSource()
                guard !Task.isCancelled, generation == id else { return }
                let input = model.localCoachRequest(message: text)
                let data = try await requestPDFText(JSONEncoder().encode(input))
                let reply = try JSONDecoder().decode(LocalCoachReply.self, from: data)
                guard !Task.isCancelled, generation == id else { return }
                requestingText = false
                // A drawing can change during a slow request. Never apply or present stale review as current.
                if originalRevision != model.mapRevision && model.session.phase.usesCanvas {
                    model.coach.say("Your map changed while I was looking. Ask again so I can use the latest drawing.")
                    draft = text
                    return
                }
                sourceReferences = model.localSourceMaterial()?.validatedReferences(reply.references) ?? []
                sourcePassages = sourceReferences.compactMap { reference in
                    model.localSourceMaterial()?.pages.first(where: { $0.page == reference.page }).map {
                        LocalSourceResult.Passage(page: $0.page, title: reference.quote ?? "Source", text: $0.text, image: "", imageData: nil)
                    }
                }
                if let answer = reply.review_answer {
                    let result = submitReviewAnswer(answer)
                    if !result.ok { model.coach.say(result.message) }
                } else { model.coach.say(reply.message) }
                if let command = reply.command {
                    let result = execute(command, callID: id.uuidString, latestRequest: latestUserRequest)
                    model.coach.say(result.message)
                }
            } catch {
                guard !Task.isCancelled, generation == id else { return }
                failedLocalMessage = userID; failedLocalText = text
                requestingText = false
                draft = text
                localError = error.localizedDescription
                model.coach.say(error.localizedDescription + " Your message is back in the input box to retry.")
            }
        }
    }

    func openSource(page: Int) {
        guard let model, page >= 1, page <= model.session.localSourcePageCount else { return }
        selectedSourcePage = page
        showingSource = true
    }

    private func localTool(name: String, arguments: Data, callID: String) async -> NativeVoiceToolResult {
        guard let model, model.session.usesPDFCoach else {
            return NativeVoiceToolResult(output: "{\"error\":\"Unsupported source\"}", images: [])
        }
        let id = generation
        do {
            switch name {
            case "get_current_map":
                let request = model.localCoachRequest(message: latestUserRequest, includeSnapshot: false)
                let data = try JSONEncoder().encode(request)
                let image = model.session.phase.usesCanvas ? CoachCanvasSnapshot.dataURL(model.map) : nil
                return NativeVoiceToolResult(output: String(data: data, encoding: .utf8) ?? "{}", images: image.map { [$0] } ?? [])
            case "cite_sources":
                struct Citation: Decodable { let page: Int; let quote: String }
                struct Input: Decodable { let citations: [Citation] }
                let input = try JSONDecoder().decode(Input.self, from: arguments)
                guard (1...3).contains(input.citations.count), let material = model.localSourceMaterial() else {
                    throw LocalCoachFailure.message("Unverified source citation")
                }
                let proposed = input.citations.map { LocalCoachReference(page: $0.page, reason: $0.quote, quote: $0.quote) }
                // Validate each quote before deduplicating display pages.
                guard proposed.allSatisfy({ material.validatedReferences([$0]).count == 1 }), generation == id else {
                    return NativeVoiceToolResult(output: "{\"ok\":false,\"error\":\"Unverified source citation\"}", images: [])
                }
                sourceReferences = material.validatedReferences(proposed)
                sourcePassages = sourceReferences.compactMap { reference in
                    material.pages.first(where: { $0.page == reference.page }).map {
                        LocalSourceResult.Passage(page: $0.page, title: reference.quote ?? material.title, text: $0.text, image: "", imageData: nil)
                    }
                }
                struct Confirmed: Encodable { let ok = true; let citations: [LocalCoachReference] }
                return NativeVoiceToolResult(output: String(data: try JSONEncoder().encode(Confirmed(citations: sourceReferences)), encoding: .utf8) ?? "{}", images: [])
            case "lookup_source":
                var query = try JSONDecoder().decode(LocalSourceQuery.self, from: arguments)
                // The model may not choose another session's source or default to the bundled demo.
                guard let sourceID = model.session.localCoachSourceID else {
                    throw LocalCoachFailure.message("Prepare this PDF in Collect first.")
                }
                query.sourceId = sourceID
                guard let material = model.localSourceMaterial() else {
                    throw LocalCoachFailure.message("Re-open this PDF in Collect and tap Retry PDF preparation.")
                }
                var result = LocalSourceResult(title: material.title,
                    passages: material.matching(query.query, pages: query.pages).map {
                        .init(page: $0.page, title: material.title, text: $0.text, image: "", imageData: nil)
                    }, note: "Extracted from the PDF attached to this session. Cite its page numbers.")
                sourcePassages = result.passages
                let images = result.passages.first.flatMap { model.sourcePageImage($0.page) }.map { [$0] } ?? []
                for i in result.passages.indices { result.passages[i].imageData = nil }
                let data = try JSONEncoder().encode(result)
                return NativeVoiceToolResult(output: "SOURCE PAGES (not learner drawing). Attached image, if any, is physical PDF page \(result.passages.first?.page ?? 1): " + (String(data: data, encoding: .utf8) ?? "{}"), images: images)
            case "submit_review_answer":
                return NativeVoiceToolResult(output: realtime.onReviewAnswer?(arguments, callID) ?? "{\"ok\":false}", images: [])
            case "apply_map_command":
                guard !localToolCalls.contains(callID) else { throw LocalCoachFailure.message("Duplicate command; nothing changed.") }
                localToolCalls.insert(callID)
                let command = try JSONDecoder().decode(CoachMapCommand.self, from: arguments)
                // The same server validator protects typed edits and live voice tool calls.
                let request = model.localCoachRequest(message: latestUserRequest, includeSnapshot: false)
                let encoded = try JSONEncoder().encode(request)
                var body = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
                body["command"] = try JSONSerialization.jsonObject(with: arguments)
                _ = try await LocalCoachGateway.post(path: "api/native/command", body: JSONSerialization.data(withJSONObject: body))
                guard !Task.isCancelled, generation == id, presentation == .voice else { throw CancellationError() }
                let result = execute(command, callID: callID, latestRequest: latestUserRequest)
                return NativeVoiceToolResult(output: String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? "{}", images: [])
            default:
                return NativeVoiceToolResult(output: "{\"error\":\"Unsupported tool\"}", images: [])
            }
        } catch {
            return NativeVoiceToolResult(output: "{\"ok\":false,\"message\":\"Request failed or became stale. Ask the learner to retry.\"}", images: [])
        }
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
                phase: snapshot.phase, canUndo: snapshot.canUndo, findings: snapshot.findings,
                localEngineShape: snapshot.localEngineShape)
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
