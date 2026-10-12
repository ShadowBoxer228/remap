import SwiftUI

/// Visual states only. Conversation and microphone ownership stay with the session.
enum CoachCharacterState: Equatable {
    case idle, connecting, listening, thinking, speaking, muted, unavailable
}

/// The original pencil, brought to life with small, cut-paper movements.
/// Its timeline is local so audio levels never invalidate the board's drawing tree.
struct CoachCharacter: View {
    var size: CGFloat = 52
    var state: CoachCharacterState = .idle
    var level: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var resting: Bool { state == .muted || state == .unavailable }
    private var animated: Bool { !reduceMotion && scenePhase == .active && !resting }
    private var energy: Double { level.isFinite ? min(1, max(0, level)) : 0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !animated)) { context in
            let time = animated ? floor(context.date.timeIntervalSinceReferenceDate * 12) / 12 : 0
            let speech = state == .speaking ? energy : 0
            let attention = state == .listening ? 1.0 : 0.0
            let tilt = animated ? sin(time * (state == .speaking ? 8 : 1.5)) * (1.5 + speech * 6) - attention * 5 : 0
            let lift = animated ? sin(time * 1.8) * size * 0.012 - speech * size * 0.025 : 0

            ZStack {
                BlobShape(seed: 7, time: time * 0.3, wobble: 0.075 + speech * 0.035)
                    .fill(state == .unavailable ? Palette.surfaceSunken : Palette.olive)
                    .grain(0.14)
                    .scaleEffect(animated ? 1 + speech * 0.035 : 1)

                Image("coach_pencil")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
                    .rotationEffect(.degrees(tilt), anchor: .bottom)
                    .offset(y: lift)

                if state == .listening || state == .speaking {
                    PencilVoiceMarks(amount: reduceMotion ? 0.4 : energy, speaking: state == .speaking)
                        .stroke(Palette.oliveDeep, style: StrokeStyle(lineWidth: max(1.3, size / 72), lineCap: .round))
                        .padding(size * 0.035)
                }
                if state == .thinking || state == .connecting {
                    HStack(spacing: size * 0.035) {
                        ForEach(0..<3) { index in
                            Capsule()
                                .fill(Palette.ink)
                                .frame(width: max(2, size * 0.035), height: max(2, size * 0.035))
                                .opacity(!animated || Int(time * 3) % 3 == index ? 1 : 0.25)
                        }
                    }
                    .padding(.horizontal, size * 0.07)
                    .padding(.vertical, size * 0.05)
                    .background(Palette.butter, in: RoundedRectangle(cornerRadius: size * 0.06))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if resting {
                    Image(systemName: state == .muted ? "mic.slash.fill" : "exclamationmark")
                        .font(.system(size: max(10, size * 0.13), weight: .semibold))
                        .foregroundStyle(state == .muted ? Palette.ink2 : Palette.accent)
                        .padding(size * 0.06)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: size * 0.06))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A few ink strokes, not an audio orb or a luminous halo.
private nonisolated struct PencilVoiceMarks: Shape {
    var amount: Double
    var speaking: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let height = rect.height
        for side in [-1.0, 1.0] {
            let x = rect.midX + side * rect.width * 0.43
            let reach = height * (0.035 + amount * 0.055)
            path.move(to: CGPoint(x: x, y: rect.midY - reach))
            path.addLine(to: CGPoint(x: x + side * height * 0.015, y: rect.midY + reach))
            if speaking {
                let outer = x + side * height * 0.065
                path.move(to: CGPoint(x: outer, y: rect.midY - reach * 0.6))
                path.addLine(to: CGPoint(x: outer, y: rect.midY + reach * 0.6))
            }
        }
        return path
    }
}
