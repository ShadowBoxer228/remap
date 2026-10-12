import Testing
import CoreGraphics
@testable import ReMap

@Suite("Layout and placement")
struct LayoutEngineTests {
    let map: MindMap = {
        let headlines = DemoContent.headlines()
        return DemoContent.regroupedMap(from: DemoContent.wrongMap(for: headlines), headlines: headlines)
    }()

    @Test("Three spread-out suggestions for a new idea")
    func threeSuggestions() {
        let placements = PlacementSuggester.suggest(for: "Calcitonin", in: map)
        #expect(placements.count == 3)
        for (i, a) in placements.enumerated() {
            for b in placements.dropFirst(i + 1) {
                #expect(a.position.distance(to: b.position) > 160)
            }
        }
        #expect(Set(placements.map(\.parentID)).count == 3, "each option tells a different story")
    }

    @Test("Suggestions never overlap existing nodes")
    func noOverlap() {
        let probe = MapNode(label: "Calcitonin", position: .zero)
        for placement in PlacementSuggester.suggest(for: probe.label, in: map) {
            var ghost = probe
            ghost.position = placement.position
            for node in map.nodes {
                #expect(!NodeMetrics.frame(for: node).intersects(NodeMetrics.frame(for: ghost)))
            }
        }
    }

    @Test("A parent already at four links is never suggested (it would become a hub)")
    func respectsHubLimit() {
        var crowded = map
        let parent = crowded.nodes[0]
        for i in 0..<MapRules.maxLinks {
            let leaf = MapNode(label: "Leaf \(i)", position: CGPoint(x: 3000 + CGFloat(i) * 300, y: 2600))
            crowded.nodes.append(leaf)
            crowded.edges.append(MapEdge(from: leaf.id, to: parent.id))
        }
        let placements = PlacementSuggester.suggest(for: "Calcitonin", in: crowded)
        #expect(!placements.contains { $0.parentID == parent.id })
    }

    @Test("Tidy keeps every node and roughly the same center")
    func tidy() {
        let positions = LayoutEngine.tidy(map)
        #expect(positions.count == map.nodes.count)
        #expect(positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        let center = positions.values.reduce(CGPoint.zero) { $0 + $1 } * (1 / CGFloat(positions.count))
        let original = map.bounds.center
        #expect(center.distance(to: original) < 1)
    }

    @Test("Link endpoints stop at the node's edge")
    func clipping() {
        let p = EdgeGeometry.clip(center: .zero, toward: CGPoint(x: 400, y: 0), size: CGSize(width: 100, height: 40), padding: 0)
        #expect(abs(p.x - 50) < 0.001 && abs(p.y) < 0.001)
    }
}
