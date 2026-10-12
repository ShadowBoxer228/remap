import Foundation

/// The part of the coach that "thinks": phrases questions and judges justifications.
/// `TemplateBrain` runs fully offline; an LLM-backed brain (on-device or cloud) can replace it.
protocol CoachBrain {
    func question(for finding: Finding, in map: MindMap, isDemo: Bool) async -> String
    func judge(reason: String, label: String, parent: String) async -> Bool
}

nonisolated struct TemplateBrain: CoachBrain {
    func question(for finding: Finding, in map: MindMap, isDemo: Bool) async -> String {
        func label(_ i: Int) -> String {
            guard finding.nodeIDs.indices.contains(i), let n = map.node(finding.nodeIDs[i]) else { return "this" }
            return n.label
        }
        switch finding.kind {
        case .hubIsTitle:
            let degree = finding.nodeIDs.first.map { map.degree(of: $0) } ?? 5
            let intro = String(localized: "“\(label(0))” has \(degree) links. When everything hangs off one node, it's a title — not an idea.")
            return intro + " " + (isDemo ? DemoContent.hubQuestion
                                  : String(localized: "Look at the ideas around it. What do some of them have in common?"))
        case .island:
            let names = finding.nodeIDs.prefix(2).compactMap { map.node($0)?.label }.joined(separator: ", ")
            return String(localized: "“\(names)” is cut off from the rest — an island. How does it connect to the main map? Draw that arrow.")
        case .missingDirection:
            return String(localized: "This link between “\(label(0))” and “\(label(1))” has no direction. Who acts on whom?")
        case .tooWordy:
            let words = finding.nodeIDs.first.flatMap { map.node($0)?.wordCount } ?? 4
            return String(localized: "“\(label(0))” is \(words) words. Say it in 1–3 — filtering is where the learning happens.")
        case .tooFewLinks:
            return String(localized: "“\(label(0))” is backbone, but it barely branches. What else does it connect to?")
        case .singleChain:
            let chain = finding.nodeIDs.compactMap { map.node($0)?.label }.joined(separator: " → ")
            return String(localized: "\(chain) reads like linear notes. What do some of these share?")
        case .noBackbone:
            return String(localized: "Which 2–4 ideas carry this whole topic? Long-press them and mark them as backbone.")
        case .unexplainedLink:
            return String(localized: "Explain this link in one sentence: how does “\(label(0))” act on “\(label(1))”?")
        }
    }

    func judge(reason: String, label: String, parent: String) async -> Bool {
        GroundingJudge.isGrounded(reason: reason, label: label, parent: parent)
    }
}

/// Heuristic check that a placement is justified by *knowledge* (a relationship), not layout.
nonisolated enum GroundingJudge {
    static let layoutWords = ["space", "fit", "empty", "room", "looks", "nice", "random", "hunch", "idk", "don't know", "dont know", "no idea", "just"]
    static let relationalWords = ["because", "cause", "lower", "raise", "increase", "decrease", "reduce", "opposite", "part of",
                                  "type of", "kind of", "leads to", "control", "regulat", "affect", "depend", "produce", "make",
                                  "inhibit", "stimulat", "therefore", "same", "balance", "than", "when", "drive", "trigger",
                                  "belongs", "acts on", "result", "so it", "like"]

    static func isGrounded(reason: String, label: String, parent: String) -> Bool {
        let r = reason.lowercased()
        let words = r.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 1 }
        guard words.count >= 4 else { return false }
        // Keep the example's known calcium relationship correct even without a model.
        let pair = (label + " " + parent).lowercased()
        if pair.contains("calcitonin"), pair.contains("calcium") {
            let lowers = ["lower", "decrease", "reduce"].contains { r.contains($0) }
            let raises = ["raise", "increase"].contains { r.contains($0) }
            let negated = ["not ", "n't", "never "].contains { r.contains($0) }
            return lowers && !raises && !negated && r.contains("calcium")
        }
        let relational = relationalWords.contains { r.contains($0) }
        let mentions = (parent + " " + label).lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .filter { $0.count > 3 }
            .contains { r.contains($0) }
        let layoutOnly = layoutWords.contains { r.contains($0) } && !relational
        return !layoutOnly && relational && mentions
    }
}
