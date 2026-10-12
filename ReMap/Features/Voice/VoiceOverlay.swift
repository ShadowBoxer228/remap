import SwiftUI

/// Borderless voice UI only. CoachConversation owns the connection across layout changes.
struct VoiceOverlay: View {
    @Bindable var model: SessionModel
    var width: CGFloat = 220
    var maxHeight: CGFloat = 300

    var body: some View {
        let conversation: CoachConversation = model.conversation
        CoachVoiceCompanion(state: CoachCharacterState(conversation.activity),
                       level: conversation.audioLevel,
                       caption: conversation.caption,
                       status: status(for: conversation.activity),
                       provider: conversation.voiceProviderLabel,
                       muted: conversation.isMicrophoneMuted,
                       error: conversation.voiceError,
                       width: width, maxHeight: maxHeight,
                       actionSummary: conversation.lastActionSummary,
                       canUndoAction: conversation.canUndoLastAction,
                       toggleMicrophone: { conversation.toggleMicrophone() },
                       openChat: { conversation.stopVoice() },
                       end: { conversation.close() },
                       retry: { Task { await conversation.retryVoice() } },
                       undo: { conversation.undoLastAction() })
    }

    private func status(for activity: CoachActivity) -> String {
        switch activity {
        case .idle: String(localized: "Ready")
        case .connecting: String(localized: "Connecting…")
        case .listening: String(localized: "Listening")
        case .thinking: String(localized: "Thinking…")
        case .speaking: String(localized: "Speaking")
        case .muted: String(localized: "Microphone off")
        case .unavailable: String(localized: "Let's reconnect")
        }
    }
}

/// The original talking figure: the same mesh, palette, contour and ink outline.
struct VoiceOrb: View {
    var state: VoiceSession.State
    var level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var energy: Double { level.isFinite ? min(1, max(0, level)) : 0 }
    private var animated: Bool { !reduceMotion && scenePhase == .active }

    private var palette: [Color] {
        switch state {
        case .listening: [Palette.butter, Palette.olive, Palette.butter, Palette.olive, Palette.highlighter, Palette.olive, Palette.butter, Palette.oliveDeep, Palette.butter]
        case .speaking: [Palette.olive, Palette.oliveDeep, Palette.olive, Palette.butter, Palette.olive, Palette.oliveDeep, Palette.olive, Palette.butter, Palette.olive]
        case .thinking: [Palette.surfaceSunken, Palette.olive, Palette.surfaceSunken, Palette.olive, Palette.butter, Palette.olive, Palette.surfaceSunken, Palette.olive, Palette.surfaceSunken]
        default: [Palette.butter, Palette.olive.opacity(0.7), Palette.butter, Palette.olive.opacity(0.7), Palette.butter, Palette.olive.opacity(0.7), Palette.butter, Palette.olive.opacity(0.7), Palette.butter]
        }
    }

    var body: some View {
        TimelineView(.animation(paused: !animated)) { context in
            let t = animated ? Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)) : 0
            let speed: Float = state == .thinking ? 0.6 : 1.3
            let activeLevel = animated ? energy : 0
            let a = 0.06 + Float(activeLevel) * 0.2
            ZStack {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5 + a * sin(t * speed * 1.3)], [0.5 + a * cos(t * speed * 1.7), 0.5 + a * sin(t * speed * 2.1)], [1, 0.5 + a * cos(t * speed)],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: palette)
                .clipShape(BlobShape(seed: 2, time: Double(t) * (state == .listening ? 2 : 0.8), wobble: 0.05 + activeLevel * 0.08))
                .grain(0.14)
                .scaleEffect(1 + activeLevel * 0.12)
                .overlay(BlobShape(seed: 2, time: Double(t) * (state == .listening ? 2 : 0.8), wobble: 0.05 + activeLevel * 0.08)
                    .stroke(Palette.ink, lineWidth: 1.5))
            }
        }
        .accessibilityHidden(true)
    }
}
