import Foundation
import CoreGraphics

/// Approximate on-canvas footprint of a node; good enough for spacing math.
nonisolated enum NodeMetrics {
    static func size(for node: MapNode) -> CGSize {
        let chars = CGFloat(max(node.label.count, 3))
        let perChar: CGFloat = node.isBackbone ? 12.5 : 10.5
        return CGSize(width: min(max(chars * perChar + 44, 96), 340), height: node.isBackbone ? 60 : 50)
    }

    static func frame(for node: MapNode) -> CGRect {
        let s = size(for: node)
        return CGRect(x: node.position.x - s.width / 2, y: node.position.y - s.height / 2, width: s.width, height: s.height)
    }
}

nonisolated extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    var length: CGFloat { (x * x + y * y).squareRoot() }
    var unit: CGPoint { let l = length; return l < 0.0001 ? CGPoint(x: 1, y: 0) : CGPoint(x: x / l, y: y / l) }
    func distance(to p: CGPoint) -> CGFloat { (self - p).length }
}

/// "Tidy up": a Fruchterman–Reingold spring layout that keeps the user's rough arrangement.
nonisolated enum LayoutEngine {
    static func tidy(_ map: MindMap, iterations: Int = 220, idealLength: CGFloat = 230) -> [UUID: CGPoint] {
        let ids = map.nodes.map(\.id)
        guard ids.count > 1 else { return Dictionary(uniqueKeysWithValues: map.nodes.map { ($0.id, $0.position) }) }
        var pos = Dictionary(uniqueKeysWithValues: map.nodes.map { ($0.id, $0.position) })
        let center = map.bounds.center
        var temperature: CGFloat = 60
        let k = idealLength
        for _ in 0..<iterations {
            var force: [UUID: CGPoint] = [:]
            for i in ids {
                var f = CGPoint.zero
                for j in ids where j != i {
                    let d = pos[i]! - pos[j]!
                    let dist = max(d.length, 1)
                    f = f + d.unit * (k * k / dist)
                }
                for j in map.neighbors(of: i) {
                    let d = pos[j]! - pos[i]!
                    f = f + d.unit * (d.length * d.length / k)
                }
                // Gentle pull to the original centroid so the map doesn't drift away.
                f = f + (center - pos[i]!) * 0.02
                force[i] = f
            }
            for i in ids {
                let f = force[i]!
                let step = min(f.length, temperature)
                pos[i] = pos[i]! + f.unit * step
            }
            temperature *= 0.975
        }
        // Re-center on the original centroid.
        let newCenter = ids.reduce(CGPoint.zero) { $0 + pos[$1]! } * (1 / CGFloat(ids.count))
        let shift = center - newCenter
        for i in ids { pos[i] = pos[i]! + shift }
        return pos
    }

    /// Positions children evenly on an arc around a parent, facing away from the map's center.
    static func fan(children: [UUID], around parent: CGPoint, awayFrom center: CGPoint, radius: CGFloat = 210) -> [UUID: CGPoint] {
        guard !children.isEmpty else { return [:] }
        let base = atan2(parent.y - center.y, parent.x - center.x)
        let spread = min(CGFloat.pi * 0.9, CGFloat(children.count) * 0.55)
        var result: [UUID: CGPoint] = [:]
        for (n, id) in children.enumerated() {
            let t = children.count == 1 ? 0.5 : CGFloat(n) / CGFloat(children.count - 1)
            let angle = base - spread / 2 + spread * t
            result[id] = CGPoint(x: parent.x + cos(angle) * radius, y: parent.y + sin(angle) * radius)
        }
        return result
    }
}

nonisolated extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

/// One suggested home for a node: next to `parentID`, at `position`.
nonisolated struct Placement: Identifiable, Equatable, Sendable {
    var id = UUID()
    var parentID: UUID
    var position: CGPoint
    var score: CGFloat
}

/// Proposes three well-spread places for a new node, each next to a different possible parent.
/// Penalizes overlaps, crossings, overloading a parent (→ hub) and leaving islands.
nonisolated enum PlacementSuggester {
    static func suggest(for label: String, in map: MindMap, excluding excluded: UUID? = nil, count: Int = 3) -> [Placement] {
        let probe = MapNode(label: label, position: .zero)
        let probeSize = NodeMetrics.size(for: probe)
        let parents = map.nodes.filter { $0.id != excluded }
        var best: [Placement] = []
        for parent in parents {
            let degree = map.degree(of: parent.id)
            if degree >= MapRules.maxLinks { continue } // would turn the parent into a hub
            var bestForParent: Placement?
            for ring in [190.0, 250.0] as [CGFloat] {
                for step in 0..<16 {
                    let angle = CGFloat(step) / 16 * 2 * .pi
                    let p = CGPoint(x: parent.position.x + cos(angle) * ring, y: parent.position.y + sin(angle) * ring)
                    let frame = CGRect(x: p.x - probeSize.width / 2 - 16, y: p.y - probeSize.height / 2 - 16,
                                       width: probeSize.width + 32, height: probeSize.height + 32)
                    var score: CGFloat = 0
                    for other in map.nodes where other.id != excluded {
                        if NodeMetrics.frame(for: other).intersects(frame) { score += 1000 }
                        let d = other.position.distance(to: p)
                        if d < 240 { score += (240 - d) * 0.6 }
                    }
                    for e in map.edges {
                        guard let a = map.node(e.from)?.position, let b = map.node(e.to)?.position else { continue }
                        if e.touches(parent.id) { continue }
                        if segmentsIntersect(parent.position, p, a, b) { score += 300 }
                    }
                    score += CGFloat(degree) * 40 // prefer parents with room to branch
                    score += ring - 190
                    if bestForParent == nil || score < bestForParent!.score {
                        bestForParent = Placement(parentID: parent.id, position: p, score: score)
                    }
                }
            }
            if let bestForParent { best.append(bestForParent) }
        }
        best.sort { $0.score < $1.score }
        // Keep the options visibly different from each other.
        var picked: [Placement] = []
        for candidate in best where picked.allSatisfy({ $0.position.distance(to: candidate.position) > 160 }) {
            picked.append(candidate)
            if picked.count == count { break }
        }
        return picked
    }

    static func segmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat { (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) }
        let d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2), d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4)
        return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
    }
}
