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
/// Motion follows the conversation: it inhales with the student's voice, pulses with its
/// own speech, orbits while thinking and rests quietly when idle or muted.
struct VoiceOrb: View {
    var state: VoiceSession.State
    var level: Double
    var muted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var follower = LevelFollower()

    private var energy: Double { level.isFinite ? min(1, max(0, level)) : 0 }
    private var animated: Bool { !reduceMotion && scenePhase == .active && !muted }
    private var listening: Bool { state == .listening && !muted }
    private var speaking: Bool { state == .speaking }
    private var thinking: Bool { state == .thinking }

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
            let now = context.date.timeIntervalSinceReferenceDate
            let t = animated ? Float(now.truncatingRemainder(dividingBy: 1000)) : 0
            let e = animated ? follower.step(toward: energy, at: now) : 0
            let speed: Float = thinking ? 0.6 : (speaking ? 1.3 + Float(e) * 1.6 : 1.3)
            let a = 0.06 + Float(e) * 0.2
            let contourTime = Double(t) * (listening ? 2 : (speaking ? 0.8 + e * 1.5 : 0.8))
            let wobble = 0.05 + e * (speaking ? 0.11 : 0.08)
            let breath = animated ? sin(now * (thinking ? 2.4 : 1.1)) : 0
            let scale: Double = muted ? 0.94
                : thinking ? 0.9 + breath * 0.02
                : listening ? 1 + e * 0.15 + breath * 0.012
                : speaking ? 1 + e * 0.13
                : 1 + breath * 0.02
            ZStack {
                if speaking && animated {
                    Circle()
                        .fill(RadialGradient(colors: [Palette.butter.opacity(0.85), Palette.butter.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: 90))
                        .scaleEffect(1.05 + e * 0.4)
                        .opacity(0.35 + e * 0.5)
                        .blur(radius: 12)
                }
                if listening && animated {
                    ForEach(0..<3, id: \.self) { index in
                        let phase = (now * (0.45 + e * 0.5) + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                        BlobShape(seed: 2, time: contourTime, wobble: 0.04)
                            .stroke(Palette.oliveDeep.opacity((1 - phase) * (0.18 + e * 0.6)), lineWidth: 1.2)
                            .scaleEffect(1 + phase * (0.22 + e * 0.3))
                    }
                }
                if thinking && animated {
                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .trim(from: 0, to: index == 0 ? 0.26 : 0.12)
                            .stroke(Palette.ink.opacity(index == 0 ? 0.7 : 0.4),
                                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 5]))
                            .rotationEffect(.degrees(now * (index == 0 ? 140 : -90) + Double(index) * 180))
                            .scaleEffect(1.12 + Double(index) * 0.08)
                    }
                }
                ReMapMeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5 + a * sin(t * speed * 1.3)], [0.5 + a * cos(t * speed * 1.7), 0.5 + a * sin(t * speed * 2.1)], [1, 0.5 + a * cos(t * speed)],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: palette)
                .clipShape(BlobShape(seed: 2, time: contourTime, wobble: wobble))
                .grain(0.14)
                .overlay(BlobShape(seed: 2, time: contourTime, wobble: wobble)
                    .stroke(Palette.ink, lineWidth: 1.5))
                .rotationEffect(.degrees(thinking && animated ? now * 18 : 0))
                .scaleEffect(scale)
                .saturation(muted ? 0.35 : 1)
                .opacity(muted ? 0.75 : 1)
            }
            .overlay(alignment: .bottomTrailing) {
                if muted {
                    Image(systemName: "mic.slash.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(6)
                        .background(Palette.surface, in: Circle())
                        .overlay(Circle().stroke(Palette.ink, lineWidth: 1))
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2), value: state)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.2), value: muted)
        .accessibilityHidden(true)
    }
}

/// Smooths per-buffer audio levels: quick attack for syllables, slower release between them.
/// A reference type so per-frame stepping never invalidates the view.
final class LevelFollower {
    private var value = 0.0
    private var last: TimeInterval = 0

    func step(toward target: Double, at now: TimeInterval) -> Double {
        let dt = last == 0 ? 0 : min(0.1, max(0, now - last))
        last = now
        let tau = target > value ? 0.06 : 0.25
        value += (target - value) * (1 - exp(-dt / tau))
        return value
    }
}

#Preview("Voice orb states") {
    TimelineView(.animation) { context in
        let t = context.date.timeIntervalSinceReferenceDate
        let voice = max(0, sin(t * 7) * 0.5 + sin(t * 3.1) * 0.4)
        HStack(spacing: 48) {
            ForEach(Array([VoiceSession.State.idle, .listening, .thinking, .speaking].enumerated()), id: \.offset) { _, state in
                VoiceOrb(state: state, level: state == .listening || state == .speaking ? voice : 0)
                    .frame(width: 140, height: 140)
            }
            VoiceOrb(state: .idle, level: 0, muted: true).frame(width: 140, height: 140)
        }
        .padding(60)
        .background(PaperBackground())
    }
}
