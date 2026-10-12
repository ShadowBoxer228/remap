import Testing
import Foundation
@testable import ReMap

@MainActor
@Suite("Session regressions")
struct SessionTests {
    private func makeModel(map: MindMap? = nil) -> SessionModel {
        let session = StudySession(title: "Test", source: SourceInfo(kind: .text, name: "Test"),
                                   headlines: DemoContent.headlines(), map: map ?? MindMap(title: "Test"), isDemo: true)
        let url = FileManager.default.temporaryDirectory.appending(path: "remap-test-\(UUID()).json")
        let store = SessionStore(preview: [session], fileURL: url)
        let model = SessionModel(session: session, store: store, ingestor: LocalSourceIngestor())
        model.coach.brain = TemplateBrain()
        return model
    }

    @Test("All isolated ideas are islands, not a clean map")
    func disconnectedIdeas() {
        let map = MindMap(title: "t", nodes: [MapNode(label: "A", position: .zero), MapNode(label: "B", position: .zero)])
        #expect(MapRules.islands(in: map).count == 1)
    }

    @Test("Skipping a problem never celebrates or claims success")
    func skipDoesNotCelebrate() async throws {
        let model = makeModel(map: MindMap(title: "t", nodes: [MapNode(label: "This label has too many words", position: .zero)]))
        model.coach.startReview()
        try await Task.sleep(for: .milliseconds(1550))
        #expect(model.coach.current?.kind == .tooWordy)
        model.coach.reply("Skip")
        try await Task.sleep(for: .milliseconds(450))
        #expect(model.celebrate == 0)
        #expect(model.coach.issueCount > 0)
        #expect(model.coach.latestCoachMessage?.text.contains("still open") == true)
        model.coach.reset()
    }

    @Test("Hub split includes the last singleton group and preserves undirected links")
    func fullGrouping() async throws {
        let model = makeModel()
        model.demoLoadWrongMap()
        model.coach.startReview()
        try await Task.sleep(for: .milliseconds(1550))
        for (name, children) in [("Blood sugar", ["Insulin", "Glucagon"]), ("Stress", ["Adrenaline", "Cortisol"]), ("Blood calcium", ["Parathormone"])] {
            model.coach.reply(name)
            for label in children {
                let node = try #require(model.map.nodes.first { $0.label == label })
                #expect(model.coach.groupingCandidates.contains(node.id))
                model.coach.assignToGroup(node.id)
            }
            model.coach.reply("Done")
        }
        #expect(model.coach.replies.contains("Make it the title"))
        model.coach.reply("Make it the title")
        #expect(model.map.title == "Hormones")
        #expect(model.map.nodes.contains { $0.label == "Blood calcium" })
        #expect(MapRules.findings(for: model.map).contains { $0.kind == .missingDirection })
        #expect(MapRules.findings(for: model.map).contains { $0.kind == .island })
        model.coach.reset()
    }

    @Test("Placing an idea is one undo step and redo restores its reason")
    func placementUndo() throws {
        let model = makeModel(map: DemoContent.regroupedMap(from: MindMap(title: "t"), headlines: DemoContent.headlines()))
        let before = model.map
        model.startPlacement(label: "Calcitonin")
        let spot = try #require(model.ghosts.first)
        model.commitPlacement(spot, reason: "It lowers blood calcium.")
        #expect(model.map.nodes.count == before.nodes.count + 1)
        model.undo()
        #expect(model.map == before)
        model.redo()
        #expect(model.map.edges.last?.reason == "It lowers blood calcium.")
    }

    @Test("Every arrow needs a reason, even on a non-backbone node")
    func leafReason() {
        let a = MapNode(label: "A", position: .zero), b = MapNode(label: "B", position: .zero)
        let map = MindMap(title: "t", nodes: [a, b], edges: [MapEdge(from: a.id, to: b.id)])
        #expect(MapRules.findings(for: map).contains { $0.kind == .unexplainedLink })
    }

    @Test("Persistence round-trips labels, roles, phase and link reasons")
    func persistence() {
        let model = makeModel()
        model.demoLoadWrongMap()
        model.rename("Saved map")
        model.advance(to: .details)
        model.store.saveNow()
        model.store.load()
        #expect(model.store.session(model.session.id)?.map == model.map)
        #expect(model.store.session(model.session.id)?.phase == .details)
    }

    @Test("Only HTTPS gateway URLs without credentials are accepted")
    func cloudURLs() {
        #expect(CoachConnection.validatedURL("https://coach.example.com") != nil)
        for raw in ["http://coach.example.com", "https://secret@example.com", "https://example.com?key=secret", "file:///tmp/a"] {
            #expect(CoachConnection.validatedURL(raw) == nil)
        }
    }

    @Test("Long group names are clarified and an empty group cannot be completed")
    func deliberateGrouping() async throws {
        let model = makeModel()
        model.demoLoadWrongMap()
        model.coach.startReview()
        try await Task.sleep(for: .milliseconds(1550))
        let count = model.map.nodes.count
        model.coach.reply("These two control blood sugar")
        #expect(model.map.nodes.count == count)
        model.coach.reply("Blood sugar")
        model.coach.reply("Done")
        if case .grouping = model.coach.mode {} else { Issue.record("Empty group was accepted") }
        #expect(model.coach.latestCoachMessage?.text.contains("at least one") == true)
        model.coach.reset()
    }

    @Test("Offline calcium check rejects the reversed fact and negation")
    func correctCalcium() {
        #expect(GroundingJudge.isGrounded(reason: "Calcitonin lowers blood calcium.", label: "Calcitonin", parent: "Blood calcium"))
        #expect(!GroundingJudge.isGrounded(reason: "Calcitonin raises blood calcium.", label: "Calcitonin", parent: "Blood calcium"))
        #expect(!GroundingJudge.isGrounded(reason: "Calcitonin does not lower blood calcium.", label: "Calcitonin", parent: "Blood calcium"))
    }
}
