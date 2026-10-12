import Foundation
import CoreGraphics
import PencilKit

nonisolated struct CoachMapAction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case addNode = "add_node", renameNode = "rename_node", deleteNode = "delete_node"
        case connect, deleteEdge = "delete_edge", setReason = "set_reason"
        case setBackbone = "set_backbone", moveNode = "move_node", renameMap = "rename_map", tidy
        case groupNodes = "group_nodes", setDirection = "set_direction", highlight, undo
    }
    var kind: Kind
    var id: UUID?
    var from: UUID?
    var to: UUID?
    var label: String?
    var reason: String?
    var x: Double?
    var y: Double?
    var backbone: Bool?
    var ids: [UUID]?
    var direction: String?
}

nonisolated struct CoachMapCommand: Codable, Sendable {
    var request: String
    var revision: UUID
    var operations: [CoachMapAction]
}

nonisolated struct CoachBoardSnapshot: Encodable {
    struct Node: Encodable { let id: UUID; let label: String; let x: Double; let y: Double; let backbone: Bool; var group: Int? }
    struct Edge: Encodable { let id: UUID; let from: UUID; let to: UUID; let reason: String; let directed: Bool }
    struct Issue: Encodable { let kind: String; let nodeIDs: [UUID]; let edgeIDs: [UUID] }
    let revision: UUID
    let title: String
    let nodes: [Node]
    let edges: [Edge]
    let selectedNode: UUID?
    let selectedEdge: UUID?
    let truncated: Bool
    var phase: String = ""
    var canUndo: Bool = false
    var findings: [Issue] = []
    /// Freehand Pencil marks that are not connections: circles, loose arrows, notes near topics.
    var ink: [InkGeometry.Mark] = []
    /// The learning-coach engine was validated against the original board fields only;
    /// it sees Pencil ink through the rendered canvas image instead.
    var localEngineShape = false

    private enum CodingKeys: String, CodingKey {
        case revision, title, nodes, edges, selectedNode, selectedEdge, truncated, phase, canUndo, findings, ink
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(revision, forKey: .revision); try c.encode(title, forKey: .title)
        try c.encode(nodes, forKey: .nodes); try c.encode(edges, forKey: .edges)
        try c.encodeIfPresent(selectedNode, forKey: .selectedNode); try c.encodeIfPresent(selectedEdge, forKey: .selectedEdge)
        try c.encode(truncated, forKey: .truncated)
        guard !localEngineShape else { return }
        try c.encode(phase, forKey: .phase); try c.encode(canUndo, forKey: .canUndo); try c.encode(findings, forKey: .findings)
        try c.encode(ink, forKey: .ink)
    }
}

extension SessionModel {
    var coachSnapshot: CoachBoardSnapshot {
        var selected: Set<UUID> = []
        if let id = selection.nodeID { selected.insert(id) }
        if let id = selection.edgeID, let edge = map.edges.first(where: { $0.id == id }) {
            selected.insert(edge.from); selected.insert(edge.to)
        }
        // Selection and discussed ideas survive truncation even near the end of a large map.
        let ordered = map.nodes.filter { selected.contains($0.id) }
            + map.nodes.filter { !selected.contains($0.id) && focus.contains($0.id) }
            + map.nodes.filter { !selected.contains($0.id) && !focus.contains($0.id) }
        let visible = Array(ordered.prefix(60))
        let ids = Set(visible.map(\.id))
        let possibleEdges = map.edges.filter { ids.contains($0.from) && ids.contains($0.to) }
        let visibleEdges = Array((possibleEdges.filter { $0.id == selection.edgeID } + possibleEdges.filter { $0.id != selection.edgeID }).prefix(80))
        let edgeIDs = Set(visibleEdges.map(\.id))
        return CoachBoardSnapshot(revision: mapRevision, title: String(map.title.prefix(200)),
            nodes: visible.map { node in
                .init(id: node.id, label: String(node.label.prefix(200)), x: node.position.x, y: node.position.y,
                      backbone: node.isBackbone || (session.usesLocalCoach && session.backboneKeywords.contains { $0.id == node.headlineID }),
                      group: session.usesLocalCoach ? nil : node.group)
            },
            edges: visibleEdges.map {
                .init(id: $0.id, from: $0.from, to: $0.to, reason: String($0.reason.prefix(200)), directed: $0.isDirected)
            }, selectedNode: selection.nodeID.flatMap { ids.contains($0) ? $0 : nil },
            selectedEdge: selection.edgeID.flatMap { edgeIDs.contains($0) ? $0 : nil },
            truncated: visible.count < map.nodes.count || visibleEdges.count < map.edges.count,
            phase: session.phase.title, canUndo: canUndo,
            findings: MapRules.findings(for: map).prefix(12).map {
                .init(kind: $0.kind.rawValue, nodeIDs: Array($0.nodeIDs.filter { ids.contains($0) }.prefix(20)),
                      edgeIDs: Array($0.edgeIDs.filter { edgeIDs.contains($0) }.prefix(20)))
            },
            ink: map.sketch.flatMap { try? PKDrawing(data: $0) }.map { InkGeometry.marks(in: $0, nodes: visible) } ?? [],
            localEngineShape: false)
    }

    /// Build a complete candidate first; any invalid operation rejects the entire transaction.
    func applyCoachCommand(_ command: CoachMapCommand, latestRequest: String) throws -> String {
        guard command.revision == mapRevision else { throw CoachCommandError.stale }
        if session.usesLocalCoach {
            guard Self.isExplicitEditRequest(latestRequest) else { throw CoachCommandError.invalid }
            let protected = Set(session.backboneKeywords.map(\.id))
            for action in command.operations {
                if let id = action.id, let node = map.node(id), let keyword = node.headlineID, protected.contains(keyword),
                   action.kind == .deleteNode || action.kind == .renameNode || (action.kind == .setBackbone && action.backbone == false) {
                    throw LocalCoachFailure.message("That is a committed Backbone keyword. It stays required; you can move it or change its connections.")
                }
            }
        }
        guard !latestRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              command.request.trimmingCharacters(in: .whitespacesAndNewlines) == latestRequest.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.operations.isEmpty, command.operations.count <= 8 else { throw CoachCommandError.invalid }
        if command.operations.contains(where: { $0.kind == .undo }) {
            guard command.operations.count == 1, canUndo else { throw CoachCommandError.invalid }
            undo()
            return String(localized: "Undid the most recent map change.")
        }
        var candidate = map
        var highlights: [UUID]?
        for action in command.operations {
            switch action.kind {
            case .addNode:
                let label = try Self.commandLabel(action.label)
                let id = action.id ?? UUID()
                guard candidate.node(id) == nil else { throw CoachCommandError.invalid }
                let center = candidate.nodes.isEmpty ? CGPoint(x: 2000, y: 1500) : candidate.bounds.center
                let position = try Self.commandPoint(action, fallback: CGPoint(x: center.x + 180, y: center.y + CGFloat(candidate.nodes.count % 3) * 90))
                let matches = session.usesLocalCoach ? session.headlines.filter { $0.text.caseInsensitiveCompare(label) == .orderedSame } : []
                let headline = matches.count == 1 ? matches.first : nil
                var node = MapNode(label: label, position: position, isBackbone: headline?.role == .backbone || (action.backbone ?? false), headlineID: headline?.id)
                node.id = id
                candidate.nodes.append(node)
            case .renameNode:
                guard let id = action.id, let index = candidate.index(of: id) else { throw CoachCommandError.missing }
                candidate.nodes[index].label = try Self.commandLabel(action.label)
            case .deleteNode:
                guard let id = action.id, candidate.node(id) != nil else { throw CoachCommandError.missing }
                candidate.nodes.removeAll { $0.id == id }; candidate.edges.removeAll { $0.touches(id) }
            case .connect:
                guard let from = action.from, let to = action.to, from != to,
                      candidate.node(from) != nil, candidate.node(to) != nil,
                      candidate.edge(between: from, and: to) == nil else { throw CoachCommandError.invalid }
                var edge = MapEdge(from: from, to: to, reason: String((action.reason ?? "").prefix(1200)))
                if let id = action.id {
                    guard candidate.edgeIndex(of: id) == nil else { throw CoachCommandError.invalid }
                    edge.id = id
                }
                candidate.edges.append(edge)
            case .deleteEdge:
                guard let id = action.id, let index = candidate.edgeIndex(of: id) else { throw CoachCommandError.missing }
                candidate.edges.remove(at: index)
            case .setReason:
                guard let id = action.id, let index = candidate.edgeIndex(of: id), let reason = action.reason, !reason.isEmpty, reason.count <= 1200 else { throw CoachCommandError.invalid }
                candidate.edges[index].reason = reason
            case .setBackbone:
                guard let id = action.id, let index = candidate.index(of: id), let flag = action.backbone else { throw CoachCommandError.invalid }
                candidate.nodes[index].isBackbone = flag
            case .moveNode:
                guard let id = action.id, let index = candidate.index(of: id), action.x != nil, action.y != nil else { throw CoachCommandError.invalid }
                candidate.nodes[index].position = try Self.commandPoint(action, fallback: .zero)
            case .renameMap: candidate.title = try Self.commandLabel(action.label)
            case .groupNodes:
                guard let members = action.ids, Set(members).count >= 2, members.count <= 20,
                      members.allSatisfy({ candidate.node($0) != nil }) else { throw CoachCommandError.invalid }
                let previous = candidate.nodes.compactMap(\.group).max() ?? -1
                guard previous < Int.max else { throw CoachCommandError.invalid }
                for index in candidate.nodes.indices where members.contains(candidate.nodes[index].id) {
                    candidate.nodes[index].group = previous + 1
                }
            case .setDirection:
                guard let id = action.id, let index = candidate.edgeIndex(of: id) else { throw CoachCommandError.missing }
                switch action.direction {
                case "forward": candidate.edges[index].isDirected = true
                case "backward":
                    let edge = candidate.edges[index]
                    candidate.edges[index].from = edge.to; candidate.edges[index].to = edge.from
                    candidate.edges[index].isDirected = true; candidate.edges[index].reason = ""
                case "none": candidate.edges[index].isDirected = false
                default: throw CoachCommandError.invalid
                }
            case .highlight:
                guard let ids = action.ids, ids.count <= 20,
                      ids.allSatisfy({ candidate.node($0) != nil || candidate.edgeIndex(of: $0) != nil }) else { throw CoachCommandError.invalid }
                highlights = ids
            case .undo: throw CoachCommandError.invalid
            case .tidy:
                let positions = LayoutEngine.tidy(candidate)
                for index in candidate.nodes.indices { if let p = positions[candidate.nodes[index].id] { candidate.nodes[index].position = p } }
            }
        }
        let changed = candidate != map
        guard changed || highlights != nil else { throw CoachCommandError.noChange }
        if changed { editMap { $0 = candidate }; selection = .none }
        if let highlights { point(at: highlights) }
        if !changed { return String(localized: "Highlighted the discussed ideas. Your map is unchanged.") }
        return String(localized: "Applied \(command.operations.count) map changes. Undo is available.")
    }

    static func isExplicitEditRequest(_ text: String) -> Bool {
        let pattern = #"(?i)^\s*(?:(?:please|okay|ok)\s*[,!]?\s*)?(?:(?:can|could|would|will) you\s+(?:please\s+)?)?(?:move|connect|link|add|create|rename|remove|delete|tidy|arrange|rearrange|set|mark|change|draw)\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func commandLabel(_ value: String?) throws -> String {
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clean.isEmpty, clean.count <= 200 else { throw CoachCommandError.invalid }
        return clean
    }

    private static func commandPoint(_ action: CoachMapAction, fallback: CGPoint) throws -> CGPoint {
        let x = action.x ?? fallback.x, y = action.y ?? fallback.y
        guard x.isFinite, y.isFinite, abs(x) <= 100000, abs(y) <= 100000 else { throw CoachCommandError.invalid }
        return CGPoint(x: x, y: y)
    }
}

nonisolated enum CoachCommandError: LocalizedError {
    case stale, invalid, missing, noChange
    var errorDescription: String? {
        switch self {
        case .stale: "The map changed while I was thinking. Please ask again using the current board."
        case .invalid: "That command could not be safely applied. Please specify the ideas and change."
        case .missing: "That idea or link is no longer on the map. Please ask again."
        case .noChange: "The map already has that state. Nothing changed."
        }
    }
}
