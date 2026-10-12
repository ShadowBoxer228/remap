import SwiftUI

/// Stop-motion timing: the animation advances in discrete frames (Vox-style cut-paper motion).
nonisolated struct SteppedAnimation: CustomAnimation {
    var duration: TimeInterval
    var fps: Double = 12

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        let frames = max(1, (duration * fps).rounded())
        let stepped = (time / duration * frames).rounded(.down) / frames
        // Ease-out between frames keeps it lively rather than mechanical.
        let eased = 1 - pow(1 - stepped, 2.2)
        return value.scaled(by: eased)
    }
}

extension Animation {
    /// Cut-paper motion at `fps` frames per second.
    static func stopMotion(duration: TimeInterval = 0.5, fps: Double = 12) -> Animation {
        Animation(SteppedAnimation(duration: duration, fps: fps))
    }
}

/// Riso-style grain over any view. Boils at 10 fps unless Reduce Motion is on.
struct GrainModifier: ViewModifier {
    var amount: CGFloat = 0.08
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)
            content.colorEffect(ShaderLibrary.grain(.float(amount), .float(t)))
        }
    }
}

/// Hand-drawn wobble, stepped like redrawn animation frames.
struct BoilModifier: ViewModifier {
    var amount: CGFloat = 1.1
    var fps: Double = 8
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / fps)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)
                content.distortionEffect(ShaderLibrary.boil(.float(t), .float(amount), .float(fps)),
                                         maxSampleOffset: CGSize(width: amount + 1, height: amount + 1))
            }
        } else {
            content
        }
    }
}

/// Re-screens content as halftone dots. `reveal` animates dots growing in.
struct HalftoneModifier: ViewModifier, Animatable {
    var cell: CGFloat = 5
    var angle: CGFloat = .pi / 4
    var ink: Color = Palette.ink
    var reveal: CGFloat = 1

    var animatableData: CGFloat {
        get { reveal }
        set { reveal = newValue }
    }

    func body(content: Content) -> some View {
        content.layerEffect(ShaderLibrary.halftone(.float(cell), .float(angle), .color(ink), .float(reveal)),
                            maxSampleOffset: CGSize(width: cell, height: cell))
    }
}

extension View {
    func grain(_ amount: CGFloat = 0.08) -> some View { modifier(GrainModifier(amount: amount)) }
    func boil(_ amount: CGFloat = 1.1, fps: Double = 8, active: Bool = true) -> some View {
        modifier(BoilModifier(amount: amount, fps: fps, active: active))
    }
    func halftone(cell: CGFloat = 5, ink: Color = Palette.ink, reveal: CGFloat = 1) -> some View {
        modifier(HalftoneModifier(cell: cell, ink: ink, reveal: reveal))
    }
}

/// A collage illustration from the asset catalog that enters like cut paper:
/// stop-motion slide with a small rotation settle, then idles with a subtle boil.
struct Illustration: View {
    var name: String
    var maxHeight: CGFloat? = nil
    var delay: Duration = .zero
    var idleBoil = true
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(maxHeight: maxHeight)
            .boil(0.8, fps: 6, active: idleBoil && shown)
            .rotationEffect(.degrees(shown ? 0 : -6))
            .offset(y: shown ? 0 : 40)
            .opacity(shown ? 1 : 0)
            .task {
                try? await Task.sleep(for: delay)
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .stopMotion(duration: 0.55, fps: 12)) { shown = true }
            }
            .accessibilityHidden(true)
    }
}

/// A grainy olive blob (the "cloud" motif) drawn in code, so it can morph and breathe.
struct GrainBlob: View {
    var color: Color = Palette.olive
    var seed: Double = 1
    var wobble: CGFloat = 0.08
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 8, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : floor(context.date.timeIntervalSinceReferenceDate * 8) / 8
            BlobShape(seed: seed, time: t, wobble: wobble)
                .fill(color)
                .grain(0.16)
        }
    }
}

nonisolated struct BlobShape: Shape {
    var seed: Double
    var time: Double
    var wobble: CGFloat
    var lobes = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let steps = 72
        var points: [CGPoint] = []
        for i in 0..<steps {
            let a = Double(i) / Double(steps) * 2 * .pi
            let n = sin(a * Double(lobes) + seed * 3.1 + time * 0.9) * 0.55
                + sin(a * 3 + seed * 1.7 - time * 0.6) * 0.45
            let rr = r * (1 - wobble + wobble * CGFloat(n))
            points.append(CGPoint(x: c.x + cos(a) * rr * (rect.width / (2 * r)), y: c.y + sin(a) * rr * (rect.height / (2 * r))))
        }
        path.move(to: CGPoint(x: (points[0].x + points[steps - 1].x) / 2, y: (points[0].y + points[steps - 1].y) / 2))
        for i in 0..<steps {
            let p = points[i], q = points[(i + 1) % steps]
            path.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
        }
        path.closeSubpath()
        return path
    }
}
