import Foundation

/// The kinds of structural problems the coach can spot in any map — no AI needed.
nonisolated enum FindingKind: String, Codable, CaseIterable, Sendable {
    /// 5+ links from one node: it's a title, not an idea.
    case hubIsTitle
    /// A cluster cut off from the rest of the map.
    case island
    /// A link that doesn't say who acts on whom.
    case missingDirection
    /// More than three words on a node — not filtered enough.
    case tooWordy
    /// A backbone node that doesn't branch (fewer than 2 links).
    case tooFewLinks
    /// A → B → C → D: linear notes drawn as a map.
    case singleChain
    /// Nothing emphasized yet.
    case noBackbone
    /// A backbone link with no one-sentence explanation.
    case unexplainedLink

    /// Lower = more fundamental; the coach raises these first.
    var priority: Int { Self.allCases.firstIndex(of: self)! }

    var symbol: String {
        switch self {
        case .hubIsTitle: "asterisk"
        case .island: "circle.dotted.and.circle"
        case .missingDirection: "arrow.left.and.right"
        case .tooWordy: "text.word.spacing"
        case .tooFewLinks: "point.topleft.down.to.point.bottomright.curvepath"
        case .singleChain: "link"
        case .noBackbone: "star"
        case .unexplainedLink: "text.bubble"
        }
    }
}

nonisolated struct Finding: Identifiable, Equatable, Sendable {
    var kind: FindingKind
    var nodeIDs: [UUID] = []
    var edgeIDs: [UUID] = []

    /// Stable identity so a finding is recognized across edits until it's fixed.
    var id: String {
        kind.rawValue + ":" + (nodeIDs.map(\.uuidString).sorted() + edgeIDs.map(\.uuidString).sorted()).joined(separator: ",")
    }
}

/// Mind-map rules from the method we teach: 1–3 words per node, 2–4 links per node,
/// every link directed and explainable in one sentence, no hubs, islands or single chains.
nonisolated enum MapRules {
    static let maxWords = 3
    static let minLinks = 2
    static let maxLinks = 4

    static func findings(for map: MindMap) -> [Finding] {
        var result: [Finding] = []
        result += hubs(in: map).map { Finding(kind: .hubIsTitle, nodeIDs: [$0]) }
        result += islands(in: map).map { Finding(kind: .island, nodeIDs: $0) }
        result += map.edges.filter { !$0.isDirected }.map {
            Finding(kind: .missingDirection, nodeIDs: [$0.from, $0.to], edgeIDs: [$0.id])
        }
        result += map.nodes.filter { $0.wordCount > maxWords }.map { Finding(kind: .tooWordy, nodeIDs: [$0.id]) }
        result += map.nodes.filter { $0.isBackbone && map.degree(of: $0.id) < minLinks && map.nodes.count > 2 }.map {
            Finding(kind: .tooFewLinks, nodeIDs: [$0.id])
        }
        result += singleChains(in: map).map { Finding(kind: .singleChain, nodeIDs: $0) }
        if map.nodes.count >= 3 && !map.nodes.contains(where: \.isBackbone) {
            result.append(Finding(kind: .noBackbone))
        }
        // Only ask for one explanation at a time — it's a Feynman check, not paperwork.
        if let edge = map.edges.first(where: { e in
            e.isDirected && e.reason.trimmingCharacters(in: .whitespaces).isEmpty
        }) {
            result.append(Finding(kind: .unexplainedLink, nodeIDs: [edge.from, edge.to], edgeIDs: [edge.id]))
        }
        return result.sorted { $0.kind.priority < $1.kind.priority }
    }

    /// Nodes with more links than an idea can carry.
    static func hubs(in map: MindMap) -> [UUID] {
        map.nodes.map(\.id).filter { map.degree(of: $0) > maxLinks }
    }

    /// Every component except the largest one is an island (an isolated node too, once the map has a body).
    static func islands(in map: MindMap) -> [[UUID]] {
        let components = map.components()
        guard components.count > 1 else { return [] }
        return Array(components.dropFirst())
    }

    /// Inner nodes needed before a path reads as linear notes. Two in a row is a normal bridge between groups.
    static let minChainInnerNodes = 3

    /// Maximal paths where ≥3 consecutive nodes have exactly two links — a list wearing a map's clothes.
    static func singleChains(in map: MindMap) -> [[UUID]] {
        let inner = Set(map.nodes.map(\.id).filter { map.degree(of: $0) == 2 })
        var visited = Set<UUID>()
        var chains: [[UUID]] = []
        for start in inner where !visited.contains(start) {
            // Grow the run of degree-2 nodes in both directions, then add the two end caps.
            var run = [start]
            visited.insert(start)
            for direction in 0..<2 {
                var previous = start
                var current = map.neighbors(of: start)[direction]
                while inner.contains(current) && !visited.contains(current) {
                    visited.insert(current)
                    if direction == 0 { run.insert(current, at: 0) } else { run.append(current) }
                    let next = map.neighbors(of: current).first { $0 != previous } ?? current
                    previous = current
                    current = next
                }
                if !run.contains(current) {
                    if direction == 0 { run.insert(current, at: 0) } else { run.append(current) }
                }
            }
            let innerCount = run.filter(inner.contains).count
            if innerCount >= minChainInnerNodes { chains.append(run) }
        }
        return chains
    }
}
