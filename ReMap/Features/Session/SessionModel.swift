import SwiftUI
import Observation

/// Viewport over the infinite canvas.
struct Camera: Equatable {
    static let minimumScale: CGFloat = 0.05
    static let maximumScale: CGFloat = 2.5
    var scale: CGFloat = 0.8
    var offset: CGSize = .zero
    var isPlaced = false

    func toWorld(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.width) / scale, y: (p.y - offset.height) / scale)
    }

    func toScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale + offset.width, y: p.y * scale + offset.height)
    }

    mutating func center(on world: CGPoint, in viewport: CGSize) {
        center(on: world, in: CGRect(origin: .zero, size: viewport))
    }

    mutating func center(on world: CGPoint, in viewport: CGRect) {
        offset = CGSize(width: viewport.midX - world.x * scale, height: viewport.midY - world.y * scale)
    }

    /// Padding is in screen points so labels retain breathing room even at a small zoom.
    mutating func fit(_ bounds: CGRect, in viewport: CGRect, padding: CGFloat = 32) {
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0,
              viewport.width > 0, viewport.height > 0 else { return }
        let inset = min(padding, min(viewport.width, viewport.height) / 4)
        let available = viewport.insetBy(dx: inset, dy: inset)
        // Fit must be allowed below the normal zoom floor for a large map in a narrow window.
        scale = min(available.width / bounds.width, available.height / bounds.height, 1.1)
        center(on: bounds.center, in: available)
    }

    /// Zoom by `factor`, keeping `anchor` (screen point) fixed under the fingers.
    mutating func zoom(by factor: CGFloat, anchor: CGPoint) {
        let newScale = min(max(scale * factor, min(scale, Self.minimumScale)), Self.maximumScale)
        let k = newScale / scale
        offset = CGSize(width: anchor.x - (anchor.x - offset.width) * k, height: anchor.y - (anchor.y - offset.height) * k)
        scale = newScale
    }
}

enum CanvasSelection: Equatable {
    case none
    case node(UUID)
    case edge(UUID)

    var nodeID: UUID? { if case .node(let id) = self { id } else { nil } }
    var edgeID: UUID? { if case .edge(let id) = self { id } else { nil } }
}

/// Everything a study session screen needs: the persisted session plus transient canvas state.
@Observable
final class SessionModel {
    private(set) var session: StudySession
    @ObservationIgnored let store: SessionStore
    @ObservationIgnored let ingestor: SourceIngesting

    // Collect
    var isExtracting = false
    var extractionMessage: String?

    // Canvas
    var selection: CanvasSelection = .none
    var editingNodeID: UUID?
    var camera = Camera()
    /// Nodes/edges the coach is pointing at.
    var focus: Set<UUID> = []
    var focusToken = 0
    /// Suggested homes for a node being placed ("where does this go?").
    var ghosts: [Placement] = []
    var placingLabel: String?
    var placingHeadlineID: UUID?
    var placingNodeID: UUID?
    /// Where a node should grow from (hub split, placement) — consumed by its entrance transition.
    var spawnOrigins: [UUID: CGPoint] = [:]
    var penMode: PenMode = .off
    var isVoiceOpen = false
    var celebrate = 0

    private var undoStack: [MindMap] = []
    private var redoStack: [MindMap] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    @ObservationIgnored private(set) var coach: CoachSession!
    @ObservationIgnored private var conversationStorage: CoachConversation!
    var conversation: CoachConversation { conversationStorage }
    private(set) var mapRevision = UUID()

    init(session: StudySession, store: SessionStore, ingestor: SourceIngesting) {
        self.session = session
        self.store = store
        self.ingestor = ingestor
        self.coach = CoachSession(model: self)
        self.conversationStorage = CoachConversation(model: self)
        if session.usesLocalCoach { self.coach.brain = LocalSessionCoachBrain(model: self) }
    }

    var map: MindMap { session.map }

    // MARK: - Session

    func update(_ body: (inout StudySession) -> Void) {
        // Editing code may read the current session while constructing the next value.
        // Never lend the observable property's inout storage across that read.
        var next = session
        body(&next)
        if next.map != session.map { mapRevision = UUID() }
        session = next
        store.update(next)
    }

    func advance(to phase: SessionPhase) {
        if session.usesLocalCoach {
            if phase > .collect && session.needsSourceUpload { return }
            if phase >= .backbone && !session.canBeginBackbone { return }
            if phase == .details && !session.missingBackboneKeywords.isEmpty {
                coach.say("Place every committed Backbone keyword before opening the full map. Structural suggestions can wait.")
                return
            }
        }
        update { s in
            s.phase = phase
            if s.reachedPhases[phase] == nil { s.reachedPhases[phase] = Date() }
        }
    }

    func rename(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        update { s in
            if s.map.title == s.title { s.map.title = t }
            s.title = t
        }
    }

    // MARK: - Collect

    /// Re-register a saved PDF against the current backend without replacing the learner's work.
    func retryPDFUpload() async {
        guard session.source.kind == .pdf, !isExtracting else { return }
        conversation.close()
        coach.pauseReview()
        conversation.sourceReferences = []
        conversation.sourcePassages = []
        conversation.showingSource = false
        update { s in
            s.source.usesLearningEngine = true
            s.source.sourceId = nil
            s.source.pageCount = nil
        }
        await collectIfNeeded()
    }

    func collectIfNeeded() async {
        guard (session.headlines.isEmpty || session.needsSourceUpload), !isExtracting else { return }
        isExtracting = true
        extractionMessage = nil
        defer { isExtracting = false }
        let originalSource = session.source
        do {
            let result = try await ingestor.ingest(originalSource)
            try Task.checkCancellation()
            guard session.source == originalSource else { return }
            update { s in
                s.source.sourceId = result.sourceId
                s.source.pageCount = result.pageCount
                if let text = result.sourceText { s.source.text = text }
                // Retried uploads must not replace manually edited or previously collected keywords.
                if s.headlines.isEmpty { s.headlines = result.headlines }
            }
            if session.usesLocalCoach { coach.brain = LocalSessionCoachBrain(model: self) }
            if !result.warnings.isEmpty { extractionMessage = result.warnings.joined(separator: " ") }
            else if session.headlines.isEmpty {
                extractionMessage = String(localized: "No headlines found. Add the ones you notice while you skim.")
            }
        } catch is CancellationError {
            extractionMessage = "PDF preparation paused. Tap Retry PDF preparation to continue."
        } catch {
            extractionMessage = error.localizedDescription
        }
    }

    func addHeadline(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, session.headlines.count < 40 else { return }
        update { $0.headlines.append(Headline(text: t)) }
    }

    func renameHeadline(_ id: UUID, to text: String) {
        guard !isCommittedBackbone(id) else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        update { s in
            guard let i = s.headlines.firstIndex(where: { $0.id == id }) else { return }
            if t.isEmpty { s.headlines.remove(at: i) } else { s.headlines[i].text = t }
        }
    }

    func removeHeadline(_ id: UUID) {
        guard !isCommittedBackbone(id) else { return }
        update { $0.headlines.removeAll { $0.id == id } }
    }

    private func isCommittedBackbone(_ id: UUID) -> Bool {
        session.isCommittedBackbone(id)
    }

    // MARK: - Sort

    func setRole(_ role: HeadlineRole?, for id: UUID) {
        guard session.canAssignRole(role, to: id) else {
            coach.say("Your Backbone keywords are committed. Keep these required ideas; Topics and Details can still be relabeled.")
            return
        }
        update { s in
            guard let i = s.headlines.firstIndex(where: { $0.id == id }) else { return }
            s.headlines[i].role = role
            if role != .detail { s.headlines[i].isFlashcard = false }
        }
    }

    func toggleFlashcard(_ id: UUID) {
        guard !isCommittedBackbone(id) else { return }
        update { s in
            guard let i = s.headlines.firstIndex(where: { $0.id == id }) else { return }
            s.headlines[i].isFlashcard.toggle()
        }
    }

    // MARK: - Map editing (undoable)

    private func pushUndo() {
        undoStack.append(session.map)
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Every structural edit goes through here so it's undoable and the coach re-checks the map.
    func editMap(undoable: Bool = true, _ body: (inout MindMap) -> Void) {
        if undoable { pushUndo() }
        update { body(&$0.map) }
        coach.mapDidChange()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(session.map)
        let sketch = session.map.sketch
        update { $0.map = previous; $0.map.sketch = sketch }
        selection = .none
        coach.mapDidChange()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(session.map)
        let sketch = session.map.sketch
        update { $0.map = next; $0.map.sketch = sketch }
        selection = .none
        coach.mapDidChange()
    }

    @discardableResult
    func addNode(_ label: String, at point: CGPoint, headlineID: UUID? = nil, backbone: Bool? = nil, from origin: CGPoint? = nil) -> UUID {
        let matched = session.usesLocalCoach ? session.headlines.filter { $0.text.caseInsensitiveCompare(label) == .orderedSame } : []
        let linkedID = headlineID ?? (matched.count == 1 ? matched.first?.id : nil)
        let headline = linkedID.flatMap { id in session.headlines.first { $0.id == id } }
        let node = MapNode(label: label, position: point,
                           isBackbone: backbone ?? (headline?.role == .backbone),
                           headlineID: linkedID)
        if let origin { spawnOrigins[node.id] = origin }
        editMap { $0.nodes.append(node) }
        return node.id
    }

    /// Called once when a drag starts, so the whole drag is one undo step.
    func beginMove() { pushUndo() }

    func moveNode(_ id: UUID, to point: CGPoint) {
        update { s in
            guard let i = s.map.index(of: id) else { return }
            s.map.nodes[i].position = point
        }
    }

    func endMove() { coach.mapDidChange() }

    func renameNode(_ id: UUID, to label: String) {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = map.index(of: id) else { return }
        if let keyword = map.nodes[i].headlineID, isCommittedBackbone(keyword) { return }
        if t.isEmpty { deleteNode(id); return }
        guard map.nodes[i].label != t else { return }
        editMap { $0.nodes[i].label = t }
    }

    func deleteNode(_ id: UUID) {
        editMap { m in
            m.nodes.removeAll { $0.id == id }
            m.edges.removeAll { $0.touches(id) }
        }
        if selection.nodeID == id { selection = .none }
    }

    func toggleBackbone(_ id: UUID) {
        guard let i = map.index(of: id) else { return }
        if let keyword = map.nodes[i].headlineID, isCommittedBackbone(keyword) { return }
        editMap { $0.nodes[i].isBackbone.toggle() }
    }

    func setGroup(_ group: Int?, for id: UUID) {
        guard let i = map.index(of: id) else { return }
        editMap { $0.nodes[i].group = group }
    }

    /// Connects two nodes; reuses an existing link instead of duplicating it.
    @discardableResult
    func connect(_ from: UUID, _ to: UUID, reason: String = "") -> UUID? {
        guard from != to, map.node(from) != nil, map.node(to) != nil else { return nil }
        if let existing = map.edge(between: from, and: to) { return existing.id }
        let edge = MapEdge(from: from, to: to, reason: reason)
        editMap { $0.edges.append(edge) }
        return edge.id
    }

    enum Direction { case forward, backward, none }

    func setDirection(_ direction: Direction, for edgeID: UUID) {
        guard let i = map.edgeIndex(of: edgeID) else { return }
        editMap { m in
            switch direction {
            case .forward: m.edges[i].isDirected = true
            case .backward:
                let edge = m.edges[i]
                m.edges[i].from = edge.to
                m.edges[i].to = edge.from
                m.edges[i].isDirected = true
            case .none: m.edges[i].isDirected = false
            }
        }
    }

    func setReason(_ reason: String, for edgeID: UUID) {
        guard let i = map.edgeIndex(of: edgeID) else { return }
        editMap(undoable: map.edges[i].reason.isEmpty) { $0.edges[i].reason = reason }
    }

    func deleteEdge(_ id: UUID) {
        editMap { $0.edges.removeAll { $0.id == id } }
        if selection.edgeID == id { selection = .none }
    }

    /// Moves `child`'s link from `oldParent` to `newParent` — the core of regrouping.
    func rewire(_ child: UUID, from oldParent: UUID, to newParent: UUID) {
        editMap { m in
            let previous = m.edge(between: child, and: oldParent)
            m.edges.removeAll { $0.touches(child) && $0.touches(oldParent) }
            if m.edge(between: child, and: newParent) == nil {
                if var edge = previous {
                    if edge.from == oldParent { edge.from = newParent }
                    if edge.to == oldParent { edge.to = newParent }
                    // A reason for the old relationship does not explain a different one.
                    edge.reason = ""
                    m.edges.append(edge)
                } else { m.edges.append(MapEdge(from: child, to: newParent)) }
            }
        }
    }

    func setPositions(_ positions: [UUID: CGPoint], undoable: Bool = true) {
        editMap(undoable: undoable) { m in
            for i in m.nodes.indices {
                if let p = positions[m.nodes[i].id] { m.nodes[i].position = p }
            }
        }
    }

    func tidy() {
        setPositions(LayoutEngine.tidy(map))
    }

    func saveSketch(_ data: Data?) {
        update { $0.map.sketch = data }
    }

    /// The old hub stops being a node and becomes the map's title.
    func promoteToTitle(_ id: UUID) {
        guard let node = map.node(id) else { return }
        editMap { m in
            m.title = node.label
            m.nodes.removeAll { $0.id == id }
            m.edges.removeAll { $0.touches(id) }
        }
        selection = .none
    }

    // MARK: - Placement ("where does this go?")

    func startPlacement(label: String, headlineID: UUID? = nil, nodeID: UUID? = nil) {
        placingLabel = label
        placingHeadlineID = headlineID
        placingNodeID = nodeID
        ghosts = PlacementSuggester.suggest(for: label, in: map, excluding: nodeID)
        coach.beginPlacement(label: label)
    }

    func cancelPlacement() {
        ghosts = []
        placingLabel = nil
        placingHeadlineID = nil
        placingNodeID = nil
    }

    /// Commits the node at a chosen ghost and links it to that ghost's parent, using the
    /// student's justification as the link's one-sentence explanation.
    func commitPlacement(_ placement: Placement, reason: String) {
        guard let label = placingLabel, let parent = map.node(placement.parentID) else { return }
        let origin = map.node(placement.parentID)?.position
        let nodeID = placingNodeID ?? UUID()
        if placingNodeID == nil { spawnOrigins[nodeID] = origin }
        editMap { m in
            if let i = m.index(of: nodeID) { m.nodes[i].position = placement.position }
            else {
                m.nodes.append(MapNode(id: nodeID, label: label, position: placement.position,
                                       isBackbone: session.headlines.first { $0.id == placingHeadlineID }?.role == .backbone,
                                       group: parent.group, headlineID: placingHeadlineID))
            }
            if let edge = m.edge(between: nodeID, and: parent.id), let i = m.edgeIndex(of: edge.id) {
                m.edges[i].reason = reason
            } else { m.edges.append(MapEdge(from: nodeID, to: parent.id, reason: reason)) }
        }
        cancelPlacement()
    }

    // MARK: - Coach focus

    func point(at ids: [UUID]) {
        focus = Set(ids)
        focusToken += 1
    }

    func clearFocus() { focus = [] }

    // MARK: - Demo controls (hidden menu — a safety net on stage)

    func demoAutoSort() {
        guard !session.usesLocalCoach else { return }
        update { s in
            for i in s.headlines.indices {
                s.headlines[i].role = DemoContent.suggestedRoles[s.headlines[i].text] ?? .detail
            }
        }
    }

    func demoLoadWrongMap() {
        guard !session.usesLocalCoach else { return }
        if session.headlines.isEmpty { update { $0.headlines = DemoContent.headlines() } }
        if session.headlines.allSatisfy({ $0.role == nil }) { demoAutoSort() }
        editMap { $0 = DemoContent.wrongMap(for: session.headlines) }
        camera.isPlaced = false
        advance(to: .backbone)
    }

    func demoRegroup() {
        guard !session.usesLocalCoach else { return }
        let target = DemoContent.regroupedMap(from: map, headlines: session.headlines)
        let hub = map.nodes.first { $0.label == "Hormones" }?.position ?? DemoContent.center
        for n in target.nodes where map.node(n.id) == nil { spawnOrigins[n.id] = hub }
        editMap { $0 = target }
        coach.mapDidChange()
    }

    func demoReset() {
        undoStack.removeAll(); redoStack.removeAll()
        cancelPlacement()
        selection = .none
        update { s in
            s.headlines = []
            s.map = MindMap(title: s.title)
            s.phase = .collect
            s.reachedPhases = [.collect: Date()]
        }
        coach.reset()
        camera = Camera()
    }
}
