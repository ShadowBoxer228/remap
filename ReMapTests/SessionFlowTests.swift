import Foundation
import Testing
@testable import ReMap

@MainActor
@Suite("Study flow to interactive map")
struct SessionFlowTests {
    private func makeModel(empty: Bool = false, phase: SessionPhase = .check) -> SessionModel {
        let backbone = Headline(text: "Water cycle", role: .backbone)
        let detail = Headline(text: "Condensation", role: .detail)
        let flashcard = Headline(text: "Boiling point", role: .detail, isFlashcard: true)
        let center = MapNode(label: backbone.text, position: CGPoint(x: 100, y: 100),
                             isBackbone: true, headlineID: backbone.id)
        let rain = MapNode(label: "Rain", position: CGPoint(x: 250, y: 100))
        let vapor = MapNode(label: "Vapor", position: CGPoint(x: 100, y: 250))
        let map = empty ? MindMap(title: "Water") : MindMap(
            title: "Water", nodes: [center, rain, vapor],
            edges: [MapEdge(from: center.id, to: rain.id, reason: "The cycle produces rain."),
                    MapEdge(from: vapor.id, to: center.id, reason: "Vapor feeds the cycle.")])
        let session = StudySession(title: "Water", source: SourceInfo(kind: .text, name: "Notes"),
                                   phase: phase, headlines: [backbone, detail, flashcard], map: map)
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "remap-flow-\(UUID()).json")
        let store = SessionStore(preview: [session], fileURL: fileURL)
        let model = SessionModel(session: session, store: store, ingestor: LocalSourceIngestor())
        model.coach.brain = TemplateBrain()
        return model
    }

    private func openMap(_ model: SessionModel) {
        model.coach.reply(String(localized: "Open mind map"))
    }

    @Test("Reflect opens the same editable map and unlocks only non-flashcard details")
    func openInteractiveMap() {
        let model = makeModel()
        let before = model.session
        #expect(model.session.unplacedHeadlines.isEmpty)

        openMap(model)

        #expect(model.session.phase == .details)
        #expect(model.session.reachedPhases[.details] != nil)
        #expect(model.map == before.map)
        #expect(model.session.headlines == before.headlines)
        #expect(model.session.sittings == before.sittings)
        #expect(model.session.unplacedHeadlines.map(\.text) == ["Condensation"])
        #expect(model.celebrate == 0)
        #expect(!model.coach.isOpen)
        model.store.load()
        #expect(model.store.session(model.session.id)?.phase == .details)
        #expect(model.store.session(model.session.id)?.map == before.map)
    }

    @Test("Empty maps and phases before Reflect cannot claim the final destination")
    func rejectPrematureCompletion() {
        for model in [makeModel(empty: true), makeModel(phase: .collect), makeModel(phase: .sort),
                      makeModel(phase: .backbone)] {
            let phase = model.session.phase
            openMap(model)
            #expect(model.session.phase == phase)
            #expect(model.session.reachedPhases[.details] == nil)
            #expect(model.celebrate == 0)
            model.coach.reset()
        }
    }

    @Test("Open questions remain truthful after the user opens their map")
    func retainOpenQuestions() {
        let model = makeModel()
        model.addNode("An isolated unfinished idea", at: .zero)
        let findings = MapRules.findings(for: model.map)
        #expect(!findings.isEmpty)
        openMap(model)
        #expect(model.session.phase == .details)
        #expect(model.coach.findings == findings)
        #expect(MapRules.findings(for: model.map) == findings)
        #expect(model.celebrate == 0)
    }

    @Test("Opening the map cancels a scheduled review without erasing conversation")
    func cancelScheduledReview() async throws {
        let model = makeModel()
        model.conversation.draft = "Keep this thought"
        model.coach.startReview()
        let message = try #require(model.coach.latestCoachMessage)
        openMap(model)
        let messagesAfterOpening = model.coach.messages
        try await Task.sleep(for: .milliseconds(1700))
        #expect(model.coach.messages == messagesAfterOpening)
        #expect(model.coach.messages.contains(message))
        #expect(model.conversation.presentation == .collapsed)
        #expect(model.conversation.draft == "Keep this thought")
        #expect(model.coach.current == nil)
        #expect(model.coach.mode == .idle)
        #expect(!model.coach.isThinking)
        #expect(model.focus.isEmpty)
        #expect(model.celebrate == 0)
    }

    @Test("A pending placement judgment cannot add a node after opening the map")
    func cancelPendingPlacement() async throws {
        let model = makeModel()
        let brain = SuspendedFlowBrain()
        model.coach.brain = brain
        let before = model.map
        model.startPlacement(label: "Condensation")
        model.coach.choose(try #require(model.ghosts.first))
        model.coach.reply("Condensation supplies rain in the cycle.")
        for _ in 0..<100 where brain.continuation == nil { await Task.yield() }
        let continuation = try #require(brain.continuation)

        openMap(model)
        continuation.resume(returning: true)
        brain.continuation = nil
        for _ in 0..<10 { await Task.yield() }

        #expect(model.map == before)
        #expect(model.session.phase == .details)
        #expect(model.ghosts.isEmpty)
        #expect(model.placingLabel == nil)
        #expect(model.coach.chosenPlacement == nil)
        #expect(!model.coach.isThinking)
    }

    @Test("Final maps remain editable with undo and survive save/reopen")
    func editAndReopen() throws {
        let model = makeModel()
        openMap(model)
        let before = model.map
        let parent = try #require(model.map.nodes.first?.id)
        let detail = model.addNode("Condensation", at: CGPoint(x: 200, y: 300))
        model.connect(detail, parent, reason: "Condensation returns water to the cycle.")
        model.renameNode(detail, to: "Cloud formation")
        model.beginMove()
        model.moveNode(detail, to: CGPoint(x: 320, y: 280))
        model.endMove()
        let edited = model.map
        model.undo()
        #expect(model.map.node(detail)?.position == CGPoint(x: 200, y: 300))
        model.redo()
        #expect(model.map == edited)
        #expect(model.map != before)
        #expect(model.session.phase == .details)
        model.store.saveNow()
        model.store.load()
        let saved = try #require(model.store.session(model.session.id))
        let reopened = SessionModel(session: saved, store: model.store, ingestor: LocalSourceIngestor())
        #expect(reopened.session.phase == .details)
        #expect(reopened.map == edited)
        #expect(reopened.session.sittings == 1)
    }

    @Test("Legacy final phase and later-session reply retain compatibility")
    func compatibility() throws {
        #expect(try JSONDecoder().decode(SessionPhase.self, from: Data("4".utf8)) == .details)
        let model = makeModel()
        model.coach.reply(String(localized: "Continue in a later session"))
        model.coach.reply(String(localized: "Continue in a later session"))
        #expect(model.session.phase == .details)
        #expect(model.session.sittings == 1)
        #expect(model.celebrate == 0)
    }

    @Test("A finished map can be reviewed again without losing its destination")
    func reviewAgain() {
        let model = makeModel()
        openMap(model)
        model.coach.startReview()
        #expect(model.session.phase == .details)
        #expect(model.coach.mode == .reviewing)
        #expect(model.coach.isOpen)
        model.coach.reset()
    }

    @Test("Reflect and Open mind map preserve active voice, draft and conversation")
    func preserveVoiceAcrossPhases() async throws {
        let model = makeModel(phase: .backbone)
        model.conversation.presentation = .voice
        model.conversation.draft = "Keep my draft"
        model.coach.say("Earlier conversation")
        let first = try #require(model.coach.messages.first)
        model.reviewMap()
        #expect(model.session.phase == .check)
        #expect(model.conversation.presentation == .voice)
        #expect(model.coach.messages.contains(first))
        model.openMindMap()
        let messages = model.coach.messages
        try await Task.sleep(for: .milliseconds(1700))
        #expect(model.session.phase == .details)
        #expect(model.conversation.presentation == .voice)
        #expect(model.conversation.draft == "Keep my draft")
        #expect(model.coach.messages == messages)
        #expect(model.coach.mode == .idle && !model.coach.isThinking)
        model.conversation.close()
    }
}

@MainActor
private final class SuspendedFlowBrain: CoachBrain {
    var continuation: CheckedContinuation<Bool, Never>?

    func question(for finding: Finding, in map: MindMap, isDemo: Bool) async -> String { "Explain the link." }

    func judge(reason: String, label: String, parent: String) async -> Bool {
        await withCheckedContinuation { continuation = $0 }
    }
}
