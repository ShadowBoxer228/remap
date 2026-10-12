import Testing
import CoreGraphics
@testable import ReMap

@Suite("Mind-map rules")
struct MapRulesTests {
    let headlines = DemoContent.headlines()

    private func node(_ label: String, _ x: CGFloat = 0, _ y: CGFloat = 0, backbone: Bool = false) -> MapNode {
        MapNode(label: label, position: CGPoint(x: x, y: y), isBackbone: backbone)
    }

    @Test("The typical first attempt trips the hub, direction and wordiness rules")
    func wrongMapFindings() {
        let map = DemoContent.wrongMap(for: headlines)
        let kinds = Set(MapRules.findings(for: map).map(\.kind))
        #expect(kinds.contains(.hubIsTitle))
        #expect(kinds.contains(.missingDirection))
        #expect(kinds.contains(.tooWordy))
        #expect(!kinds.contains(.island))

        let hub = MapRules.findings(for: map).first { $0.kind == .hubIsTitle }
        #expect(hub.flatMap { map.node($0.nodeIDs[0])?.label } == "Hormones")
    }

    @Test("Hub is the first thing the coach raises")
    func priorityOrder() {
        let findings = MapRules.findings(for: DemoContent.wrongMap(for: headlines))
        #expect(findings.first?.kind == .hubIsTitle)
    }

    @Test("Regrouped by function, the map passes every structural rule")
    func regroupedMapIsClean() {
        let wrong = DemoContent.wrongMap(for: headlines)
        let map = DemoContent.regroupedMap(from: wrong, headlines: headlines)
        #expect(MapRules.findings(for: map).isEmpty, "\(MapRules.findings(for: map).map(\.kind))")
        #expect(map.title == "Hormones")
        #expect(map.node(map.nodes.first { $0.label == "Insulin" }!.id) != nil)
    }

    @Test("Regrouping keeps node identity, so nodes animate to their new homes")
    func regroupKeepsIDs() {
        let wrong = DemoContent.wrongMap(for: headlines)
        let regrouped = DemoContent.regroupedMap(from: wrong, headlines: headlines)
        let insulinBefore = wrong.nodes.first { $0.label == "Insulin" }!.id
        let insulinAfter = regrouped.nodes.first { $0.label == "Insulin" }!.id
        #expect(insulinBefore == insulinAfter)
    }

    @Test("Five links make a hub; four is fine", arguments: [4, 5, 6])
    func hubThreshold(spokes: Int) {
        var map = MindMap(title: "t")
        let hub = node("Hub")
        map.nodes.append(hub)
        for i in 0..<spokes {
            let n = node("N\(i)", CGFloat(i) * 100, 200)
            map.nodes.append(n)
            map.edges.append(MapEdge(from: hub.id, to: n.id))
        }
        #expect(MapRules.hubs(in: map).contains(hub.id) == (spokes > MapRules.maxLinks))
    }

    @Test("Labels: up to three words is fine")
    func wordiness() {
        #expect(node("Blood sugar").wordCount == 2)
        #expect(node("Made by beta cells").wordCount == 4)
        var map = MindMap(title: "t", nodes: [node("Fight or flight"), node("Long term stress response")])
        map.edges = [MapEdge(from: map.nodes[0].id, to: map.nodes[1].id)]
        let wordy = MapRules.findings(for: map).filter { $0.kind == .tooWordy }
        #expect(wordy.count == 1)
        #expect(wordy.first?.nodeIDs == [map.nodes[1].id])
    }

    @Test("A disconnected cluster is reported as an island")
    func islands() {
        let a = node("A"), b = node("B"), c = node("C"), d = node("D")
        let map = MindMap(title: "t", nodes: [a, b, c, d],
                          edges: [MapEdge(from: a.id, to: b.id), MapEdge(from: b.id, to: c.id)])
        let islands = MapRules.islands(in: map)
        #expect(islands == [[d.id]])
    }

    @Test("Linear notes: three inner nodes in a row form a single chain; two don't")
    func singleChains() {
        func chain(_ count: Int) -> MindMap {
            let nodes = (0..<count).map { node("N\($0)", CGFloat($0) * 100) }
            let edges = zip(nodes, nodes.dropFirst()).map { MapEdge(from: $0.id, to: $1.id) }
            return MindMap(title: "t", nodes: nodes, edges: edges)
        }
        #expect(MapRules.singleChains(in: chain(4)).isEmpty)
        let long = chain(5)
        let found = MapRules.singleChains(in: long)
        #expect(found.count == 1)
        #expect(Set(found[0]) == Set(long.nodes.map(\.id)))
    }

    @Test("An undirected link is flagged; directing it resolves the finding")
    func direction() {
        let a = node("Stress"), b = node("Blood sugar")
        var map = MindMap(title: "t", nodes: [a, b], edges: [MapEdge(from: a.id, to: b.id, isDirected: false)])
        #expect(MapRules.findings(for: map).contains { $0.kind == .missingDirection })
        map.edges[0].isDirected = true
        #expect(!MapRules.findings(for: map).contains { $0.kind == .missingDirection })
    }

    @Test("Finding identity is stable across unrelated edits")
    func stableFindingIDs() {
        var map = DemoContent.wrongMap(for: headlines)
        let before = MapRules.findings(for: map).first { $0.kind == .hubIsTitle }!.id
        map.nodes[1].position.x += 40
        let after = MapRules.findings(for: map).first { $0.kind == .hubIsTitle }!.id
        #expect(before == after)
    }
}

@Suite("Coach helpers")
struct CoachHelperTests {
    @Test("A knowledge-based reason is grounded; a layout reason is not")
    func grounding() {
        #expect(GroundingJudge.isGrounded(reason: "It lowers blood calcium — the opposite of parathormone",
                                          label: "Calcitonin", parent: "Blood calcium"))
        #expect(!GroundingJudge.isGrounded(reason: "There was free space there", label: "Calcitonin", parent: "Stress"))
        #expect(!GroundingJudge.isGrounded(reason: "calcium", label: "Calcitonin", parent: "Blood calcium"))
    }

    @Test("Group names are trimmed to three capitalized words")
    func groupNames() {
        #expect(CoachSession.cleanGroupName("blood sugar.") == "Blood sugar")
        #expect(CoachSession.cleanGroupName("  how the body handles stress ") == "How the body")
    }

    @Test("Pasted notes yield their headings")
    func textHeadlines() {
        let text = """
        # Photosynthesis
        Plants turn light into sugar.
        ## Light reactions
        They happen in the thylakoids.
        ## Calvin cycle
        """
        let titles = TextHeadlineExtractor.headlines(from: text).map(\.text)
        #expect(titles.prefix(3) == ["Photosynthesis", "Light reactions", "Calvin cycle"])
    }
}
