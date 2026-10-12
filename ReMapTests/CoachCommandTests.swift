import Foundation
import Testing
@testable import ReMap

@MainActor
@Suite("Coach command transactions")
struct CoachCommandTests {
    private func model() -> SessionModel {
        let session = StudySession(title: "Test", source: SourceInfo(kind: .text, name: "Test"),
            map: MindMap(title: "Test", nodes: [MapNode(label: "First", position: .zero), MapNode(label: "Second", position: .init(x: 200, y: 0))]))
        let store = SessionStore(preview: [session], fileURL: FileManager.default.temporaryDirectory.appending(path: "commands-\(UUID()).json"))
        return SessionModel(session: session, store: store, ingestor: LocalSourceIngestor())
    }

    @Test("Multiple approved operations form one reversible transaction")
    func atomicUndo() throws {
        let m = model(), before = m.map
        let command = CoachMapCommand(request: "Rename First and link the ideas", revision: m.mapRevision, operations: [
            .init(kind: .renameNode, id: m.map.nodes[0].id, label: "New name"),
            .init(kind: .connect, from: m.map.nodes[0].id, to: m.map.nodes[1].id)
        ])
        _ = try m.applyCoachCommand(command, latestRequest: command.request)
        #expect(m.map.nodes[0].label == "New name")
        #expect(m.map.edges.count == 1)
        m.undo(); #expect(m.map == before)
        m.redo(); #expect(m.map.nodes[0].label == "New name")
    }

    @Test("Stale revision and mismatched latest request cannot mutate the board")
    func staleOrDifferentRequest() throws {
        let m = model()
        let command = CoachMapCommand(request: "Rename First", revision: m.mapRevision, operations: [.init(kind: .renameNode, id: m.map.nodes[0].id, label: "Changed")])
        #expect(throws: CoachCommandError.self) { try m.applyCoachCommand(command, latestRequest: "Explain First") }
        m.moveNode(m.map.nodes[1].id, to: .init(x: 400, y: 200))
        #expect(throws: CoachCommandError.self) { try m.applyCoachCommand(command, latestRequest: command.request) }
        #expect(m.map.nodes[0].label == "First")
    }

    @Test("An invalid later operation rolls back the entire proposed command")
    func invalidBatch() throws {
        let m = model(), before = m.map
        let command = CoachMapCommand(request: "Edit this map", revision: m.mapRevision, operations: [
            .init(kind: .renameNode, id: m.map.nodes[0].id, label: "Changed"),
            .init(kind: .deleteNode, id: UUID())
        ])
        #expect(throws: CoachCommandError.self) { try m.applyCoachCommand(command, latestRequest: command.request) }
        #expect(m.map == before); #expect(!m.canUndo)
    }

    @Test("Backgrounding a collapsed conversation does not open chat")
    func inactiveCollapsed() {
        let m = model()
        m.conversation.sceneBecameInactive()
        #expect(m.conversation.presentation == .collapsed)
        #expect(m.conversation.caption.isEmpty)
    }
    @Test("Grouping and reversing a link are one undo; highlights preserve map and camera")
    func groupDirectionAndHighlight() throws {
        let m = model()
        _ = m.connect(m.map.nodes[0].id, m.map.nodes[1].id)
        let before = m.map, camera = m.camera
        let edit = CoachMapCommand(request: "Group these and reverse the link", revision: m.mapRevision, operations: [
            .init(kind: .groupNodes, ids: m.map.nodes.map(\.id)),
            .init(kind: .setDirection, id: m.map.edges[0].id, direction: "backward")
        ])
        _ = try m.applyCoachCommand(edit, latestRequest: edit.request)
        #expect(m.map.nodes[0].group == m.map.nodes[1].group)
        #expect(m.map.nodes[0].group != nil)
        #expect(m.map.edges[0].from == before.edges[0].to)
        let undo = CoachMapCommand(request: "Undo that", revision: m.mapRevision, operations: [.init(kind: .undo)])
        _ = try m.applyCoachCommand(undo, latestRequest: undo.request)
        #expect(m.map == before)
        let highlight = CoachMapCommand(request: "Explain First", revision: m.mapRevision, operations: [.init(kind: .highlight, ids: [m.map.nodes[0].id])])
        _ = try m.applyCoachCommand(highlight, latestRequest: highlight.request)
        #expect(m.map == before)
        #expect(m.focus == [m.map.nodes[0].id])
        #expect(m.camera.scale == camera.scale)
        #expect(m.camera.offset == camera.offset)
    }

    @Test("Large snapshots retain the selected node, phase and only relevant findings")
    func selectedSnapshot() {
        let m = model()
        m.editMap { map in
            for index in 0..<80 { map.nodes.append(MapNode(label: "Idea \(index)", position: .init(x: index * 100, y: 0))) }
        }
        let selected = m.map.nodes.last!.id
        m.selection = .node(selected)
        m.focus = Set(m.map.nodes.map(\.id))
        let snapshot = m.coachSnapshot
        #expect(snapshot.nodes.count == 60)
        #expect(snapshot.nodes.first?.id == selected)
        #expect(snapshot.selectedNode == selected)
        #expect(snapshot.truncated)
        #expect(!snapshot.phase.isEmpty)
        #expect(!snapshot.findings.isEmpty)
    }

    @Test("Chat mode changes preserve draft and history without a voice connection")
    func sharedConversationState() {
        let m = model()
        m.conversation.openChat()
        m.conversation.draft = "A thought to finish"
        let messages = m.coach.messages
        m.conversation.close()
        m.conversation.openChat()
        #expect(m.conversation.draft == "A thought to finish")
        #expect(m.coach.messages == messages)
        #expect(m.conversation.presentation == .chat)
    }

    @Test("Repeated provider call IDs never apply the same edit twice")
    func repeatedCall() {
        let m = model(), before = m.map
        let command = CoachMapCommand(request: "Rename First", revision: m.mapRevision, operations: [.init(kind: .renameNode, id: m.map.nodes[0].id, label: "Changed")])
        let first = m.conversation.execute(command, callID: "call-one", latestRequest: command.request)
        #expect(first.ok)
        let second = m.conversation.execute(command, callID: "call-one", latestRequest: command.request)
        #expect(!second.ok)
        #expect(second.message.contains("already handled"))
        #expect(m.conversation.canUndoLastAction)
        m.conversation.undoLastAction()
        #expect(m.map == before)
        #expect(!m.conversation.canUndoLastAction)
    }

    @Test("Starting review preserves the unified conversation and unfinished draft")
    func reviewPreservesHistory() {
        let m = model()
        m.coach.brain = TemplateBrain()
        m.coach.messages = [.init(text: "My earlier question", fromUser: true), .init(text: "Earlier voice answer")]
        m.conversation.draft = "Unfinished thought"
        let history = m.coach.messages
        m.coach.startReview()
        #expect(Array(m.coach.messages.prefix(2)) == history)
        #expect(m.conversation.draft == "Unfinished thought")
        m.coach.pauseReview()
        m.coach.reset()
        #expect(m.coach.messages.isEmpty)
    }

}
