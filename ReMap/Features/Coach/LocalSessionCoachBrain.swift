import Foundation

/// Existing placement/review UI can ask our engine without starting a second conversation service.
final class LocalSessionCoachBrain: CoachBrain {
    private weak var model: SessionModel?
    init(model: SessionModel) { self.model = model }
    func question(for finding: Finding, in map: MindMap, isDemo: Bool) async -> String {
        guard let model else { return "What relationship do you want this part of the map to express?" }
        guard !model.session.needsSourceUpload else { return "Prepare your PDF in Collect before asking source questions." }
        do {
            let labels = finding.nodeIDs.compactMap { map.node($0)?.label }.joined(separator: ", ")
            let request = model.localCoachRequest(message: "Ask one reflective question about these ideas in my map: " + labels)
            let data = try await LocalCoachGateway.post(path: "api/native/coach", body: JSONEncoder().encode(request))
            return try JSONDecoder().decode(LocalCoachReply.self, from: data).message
        } catch { return "How do these ideas connect? You can keep editing and return to this question." }
    }
    func judge(reason: String, label: String, parent: String) async -> Bool {
        // Placement requires the learner's explanation, not model approval.
        // Source-based feedback remains conversational and may challenge it afterwards.
        reason.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).count >= 3
    }
}
