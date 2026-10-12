import SwiftUI

/// Bounded text conversation. The launcher now belongs to the session header.
struct CoachPanel: View {
    @Bindable var model: SessionModel
    var coach: CoachSession
    @Binding var draft: String
    var width: CGFloat = 340
    var maxHeight: CGFloat = 480
    var compactPill = false

    var body: some View {
        let conversation: CoachConversation = model.conversation
        if conversation.presentation == .chat {
            CoachChatCard(coach: coach, draft: $draft,
                          status: statusLine, thinking: coach.isThinking || conversation.activity == .thinking,
                          width: width, maxHeight: maxHeight,
                          actionSummary: conversation.lastActionSummary,
                          canUndoAction: conversation.canUndoLastAction,
                          send: { conversation.send($0) },
                          startVoice: { Task { await conversation.startVoice() } },
                          close: { conversation.close() },
                          review: offersReview ? { coach.startReview() } : nil,
                          undo: { conversation.undoLastAction() })
        }
    }

    private var offersReview: Bool {
        if case .grouping = coach.mode { return false }
        return coach.mode != .reviewing && coach.mode != .placing
            && !coach.replies.contains(String(localized: "Check my map"))
    }

    private var statusLine: String {
        if model.session.usesLocalCoach { return "Think it through, together" }
        if model.map.nodes.isEmpty { return String(localized: "Start with an idea") }
        switch coach.mode {
        case .idle: return String(localized: "Think it through, together")
        case .reviewing: return String(localized: "\(coach.resolvedCount) fixed · \(coach.issueCount) to go")
        case .grouping: return String(localized: "Building a group")
        case .placing: return String(localized: "Finding a home")
        case .finished: return coach.issueCount == 0 ? String(localized: "Review complete") : String(localized: "Questions still open")
        }
    }
}

/// Three ink dots that "boil" while the coach thinks.
struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate * 8)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Palette.ink)
                        .frame(width: 8, height: 8)
                        .offset(y: (frame + i) % 3 == 0 ? -4 : 0)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityLabel(Text("Coach is thinking"))
    }
}
