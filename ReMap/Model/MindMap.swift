import Foundation
import CoreGraphics

nonisolated struct MapNode: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var label: String
    var position: CGPoint
    /// Emphasized as part of the map's backbone.
    var isBackbone = false
    /// Index into the branch palette.
    var group: Int? = nil
    /// The collected headline this node came from, if any.
    var headlineID: UUID? = nil

    var wordCount: Int {
        label.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "/" }).count
    }
}

nonisolated struct MapEdge: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var from: UUID
    var to: UUID
    /// Every arrow should say who acts on whom.
    var isDirected = true
    /// The one-sentence explanation of the relationship.
    var reason = ""

    func touches(_ node: UUID) -> Bool { from == node || to == node }
    func other(than node: UUID) -> UUID { from == node ? to : from }
}

nonisolated struct MindMap: Codable, Equatable, Sendable {
    var title: String
    var nodes: [MapNode] = []
    var edges: [MapEdge] = []
    /// Freehand PencilKit layer (`PKDrawing.dataRepresentation()`).
    var sketch: Data? = nil

    func node(_ id: UUID) -> MapNode? { nodes.first { $0.id == id } }
    func index(of id: UUID) -> Int? { nodes.firstIndex { $0.id == id } }
    func edgeIndex(of id: UUID) -> Int? { edges.firstIndex { $0.id == id } }

    func edges(touching id: UUID) -> [MapEdge] { edges.filter { $0.touches(id) } }
    func degree(of id: UUID) -> Int { edges.reduce(0) { $0 + ($1.touches(id) ? 1 : 0) } }
    func neighbors(of id: UUID) -> [UUID] { edges(touching: id).map { $0.other(than: id) } }

    func edge(between a: UUID, and b: UUID) -> MapEdge? {
        edges.first { ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a) }
    }

    /// Connected components, largest first.
    func components() -> [[UUID]] {
        var seen = Set<UUID>()
        var result: [[UUID]] = []
        var adjacency: [UUID: [UUID]] = [:]
        for e in edges {
            adjacency[e.from, default: []].append(e.to)
            adjacency[e.to, default: []].append(e.from)
        }
        for n in nodes where !seen.contains(n.id) {
            var stack = [n.id]
            var component: [UUID] = []
            seen.insert(n.id)
            while let current = stack.popLast() {
                component.append(current)
                for next in adjacency[current, default: []] where !seen.contains(next) {
                    seen.insert(next)
                    stack.append(next)
                }
            }
            result.append(component)
        }
        return result.sorted { $0.count > $1.count }
    }

    var bounds: CGRect {
        guard let first = nodes.first else { return .zero }
        var rect = CGRect(origin: first.position, size: .zero)
        for n in nodes { rect = rect.union(CGRect(origin: n.position, size: .zero)) }
        return rect
    }
}
