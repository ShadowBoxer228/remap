import Foundation

/// The source and keywords used by the working local coaching engine.
/// The designer's original Endocrine demo remains in DemoContent.swift.
nonisolated enum TrainingLLMContent {
    static let sourceID = "training-llm"
    static let pdfName = "TrainingLLM"
    static let title = "Training an LLM"
    static let attribution = "Introduction to LLM development — Marco Kuhlmann, Linköping University · CC BY 4.0"
    static let outline: [(String, Int)] = [
        ("Pretraining", 7),
        ("Training data", 10),
        ("Instruction tuning", 7),
        ("Model architecture", 3),
        ("Human preferences", 7),
        ("Compute & GPUs", 12),
        ("Next-token prediction", 7),
        ("Reward modelling", 7),
        ("Evaluation", 15),
        ("Reinforcement learning", 7),
        ("Mixture of experts", 5),
        ("Data quality", 7)
    ]
    static func headlines() -> [Headline] {
        outline.map { Headline(text: $0.0, page: $0.1) }
    }
}

nonisolated extension StudySession {
    var isTrainingDemo: Bool { source.kind == .demo && source.name == "TrainingLLM.pdf" }
    /// PDFs always use this engine, including pending/failed uploads. Never fall back to legacy content.
    var usesLocalCoach: Bool { isTrainingDemo || (source.kind == .pdf && source.usesLearningEngine == true) }
    var localCoachSourceID: String? { isTrainingDemo ? TrainingLLMContent.sourceID : source.sourceId }
    var needsSourceUpload: Bool { source.kind == .pdf && source.usesLearningEngine == true && (source.sourceId == nil || source.text == nil) }
    var localSourcePageCount: Int { isTrainingDemo ? 18 : (source.pageCount ?? 0) }
    var backboneKeywords: [Headline] { headlines(for: .backbone) }
    func isCommittedBackbone(_ id: UUID) -> Bool {
        usesLocalCoach && reachedPhases[.backbone] != nil && backboneKeywords.contains { $0.id == id }
    }
    func canAssignRole(_ role: HeadlineRole?, to id: UUID) -> Bool {
        guard usesLocalCoach && reachedPhases[.backbone] != nil else { return true }
        if isCommittedBackbone(id) { return role == .backbone }
        // Older designer PDF sessions could commit two keywords. Allow repairing that minimum.
        return role != .backbone || backboneKeywords.count < 3
    }
    var canBeginBackbone: Bool {
        !usesLocalCoach || ((3...5).contains(backboneKeywords.count) && headlines.allSatisfy { $0.role != nil })
    }
    var missingBackboneKeywords: [Headline] {
        let represented = Set(map.nodes.compactMap(\.headlineID))
        return backboneKeywords.filter { !represented.contains($0.id) }
    }
}
