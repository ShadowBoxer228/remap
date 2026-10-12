import Foundation

extension SessionModel {
    func reviewMap() {
        guard !map.nodes.isEmpty else { return }
        selection = .none
        if conversation.presentation != .voice { conversation.openChat() }
        coach.startReview()
    }

    /// Reflection ends in the same board, with details unlocked and all edits intact.
    /// Entering this workspace does not assert that the map passed every review rule.
    func openMindMap() {
        guard session.phase >= .check, !map.nodes.isEmpty else { return }
        if session.usesLocalCoach && !session.missingBackboneKeywords.isEmpty {
            coach.say("Place every committed Backbone keyword first. Other structural suggestions can wait.")
            return
        }
        coach.pauseReview()
        coach.replies = []
        conversation.prepareForPhaseChange()
        if conversation.presentation != .voice { conversation.close() }
        selection = .none
        editingNodeID = nil
        advance(to: .details)
        store.saveNow()
    }
}
