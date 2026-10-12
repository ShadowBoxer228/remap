import Foundation
import CoreGraphics

/// The pitch scenario: an endocrine-system chapter organized "by organ" (like most textbooks),
/// which the student learns to regroup "by function". Facts are physiologically correct:
/// insulin lowers blood glucose, glucagon raises it; adrenaline = short-term stress, cortisol = long-term;
/// calcitonin lowers blood calcium, parathormone raises it.
nonisolated enum DemoContent {
    static let title = "Endocrine Basics"
    static let pdfName = "EndocrineBasics"

    /// Outline of the bundled PDF, in textbook (by-organ) order.
    static let outline: [(text: String, level: Int, page: Int)] = [
        ("Hormones", 0, 1),
        ("Pancreas", 0, 2), ("Insulin", 1, 2), ("Glucagon", 1, 2), ("Beta cells", 1, 3),
        ("Adrenal glands", 0, 4), ("Adrenaline", 1, 4), ("Cortisol", 1, 5),
        ("Thyroid gland", 0, 6), ("Calcitonin", 1, 6),
        ("Parathyroid glands", 0, 7), ("Parathormone", 1, 7),
        ("Negative feedback", 0, 8),
    ]

    static func headlines() -> [Headline] {
        outline.map { Headline(text: $0.text, page: $0.page, level: $0.level) }
    }

    /// A reasonable sorting, used by the hidden demo menu ("Auto-sort").
    static let suggestedRoles: [String: HeadlineRole] = [
        "Hormones": .backbone,
        "Insulin": .topic, "Glucagon": .topic, "Adrenaline": .topic, "Cortisol": .topic,
        "Calcitonin": .topic, "Parathormone": .topic,
        "Pancreas": .detail, "Adrenal glands": .detail, "Thyroid gland": .detail, "Parathyroid glands": .detail,
        "Beta cells": .detail, "Negative feedback": .detail,
    ]

    static let center = CGPoint(x: 1500, y: 1000)

    /// What students typically draw first: one hub with every hormone hanging off it,
    /// a link without direction, and a node that's a whole sentence.
    static func wrongMap(for headlines: [Headline]) -> MindMap {
        func id(_ text: String) -> UUID? { headlines.first { $0.text == text }?.id }
        let hub = MapNode(label: "Hormones", position: center, isBackbone: true, headlineID: id("Hormones"))
        let spokes = ["Insulin", "Glucagon", "Adrenaline", "Cortisol", "Parathormone"]
        var nodes = [hub]
        var edges: [MapEdge] = []
        for (i, name) in spokes.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(i) / CGFloat(spokes.count) * 2 * .pi
            let node = MapNode(label: name, position: CGPoint(x: center.x + cos(angle) * 270, y: center.y + sin(angle) * 230),
                               headlineID: id(name))
            nodes.append(node)
            edges.append(MapEdge(from: hub.id, to: node.id, isDirected: name != "Glucagon"))
        }
        let insulin = nodes[1]
        let wordy = MapNode(label: "Made by beta cells in the pancreas",
                            position: CGPoint(x: insulin.position.x + 40, y: insulin.position.y - 150))
        nodes.append(wordy)
        edges.append(MapEdge(from: insulin.id, to: wordy.id))
        return MindMap(title: title, nodes: nodes, edges: edges)
    }

    /// The same knowledge regrouped by what the hormones *do*. Calcitonin is left for the
    /// "where does it go?" placement moment. The old hub becomes the map's title.
    static func regroupedMap(from map: MindMap, headlines: [Headline]) -> MindMap {
        func existing(_ label: String) -> MapNode? { map.nodes.first { $0.label == label } }
        func id(_ text: String) -> UUID? { headlines.first { $0.text == text }?.id }
        func node(_ label: String, _ x: CGFloat, _ y: CGFloat, backbone: Bool = false, group: Int?) -> MapNode {
            var n = existing(label) ?? MapNode(label: label, position: .zero, headlineID: id(label))
            n.position = CGPoint(x: center.x + x, y: center.y + y)
            n.isBackbone = backbone
            n.group = group
            return n
        }
        let sugar = node("Blood sugar", -300, -110, backbone: true, group: 0)
        let stress = node("Stress", 300, -110, backbone: true, group: 1)
        let calcium = node("Blood calcium", 60, 260, backbone: true, group: 2)
        let insulin = node("Insulin", -540, -260, group: 0)
        let glucagon = node("Glucagon", -560, 40, group: 0)
        let adrenaline = node("Adrenaline", 540, -260, group: 1)
        let cortisol = node("Cortisol", 470, 120, group: 1)
        let pth = node("Parathormone", -230, 330, group: 2)
        let nodes = [sugar, stress, calcium, insulin, glucagon, adrenaline, cortisol, pth]
        let edges = [
            MapEdge(from: insulin.id, to: sugar.id, reason: "Insulin lowers blood sugar."),
            MapEdge(from: glucagon.id, to: sugar.id, reason: "Glucagon raises blood sugar."),
            MapEdge(from: adrenaline.id, to: stress.id, reason: "Adrenaline drives the short-term stress spike."),
            MapEdge(from: cortisol.id, to: stress.id, reason: "Cortisol sustains the long-term stress response."),
            MapEdge(from: stress.id, to: sugar.id, reason: "Stress hormones push blood sugar up for energy."),
            MapEdge(from: pth.id, to: calcium.id, reason: "Parathormone raises blood calcium."),
            MapEdge(from: cortisol.id, to: calcium.id, reason: "Chronic cortisol thins bone and drains calcium."),
        ]
        return MindMap(title: "Hormones", nodes: nodes, edges: edges, sketch: map.sketch)
    }

    /// Scripted coach lines layered on top of the generic coach for this topic.
    static let hubQuestion = "Look at insulin and glucagon. Forget where they come from — what do they both change?"
    static let hubSuggestedAnswers = ["Blood sugar", "They both come from the pancreas", "I'm not sure"]
    static let organAnswerReply = "That's *where* they come from. A map sorted by organ is just an address book. What do they *do*?"
    static let groupFollowUps: [String: String] = [
        "blood sugar": "Exactly — insulin lowers it, glucagon raises it. Now adrenaline and cortisol: what do they share?",
        "stress": "Yes. Adrenaline is the short spike, cortisol the long tail. And parathormone?",
        "calcium": "Right — blood calcium. You just rebuilt the chapter around function, not anatomy.",
    ]
    static let placementReasonSuggestions: [String: [String]] = [
        "Calcitonin": ["It lowers blood calcium — the opposite of parathormone", "There was free space there"],
    ]
}
