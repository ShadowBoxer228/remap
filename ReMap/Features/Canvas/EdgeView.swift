import SwiftUI

/// Pure geometry for links between nodes.
nonisolated enum EdgeGeometry {
    /// Where the line from `center` toward `target` leaves the node's rounded box.
    static func clip(center: CGPoint, toward target: CGPoint, size: CGSize, padding: CGFloat = 8) -> CGPoint {
        let d = target - center
        let hw = size.width / 2 + padding, hh = size.height / 2 + padding
        guard abs(d.x) > 0.001 || abs(d.y) > 0.001 else { return center }
        let tx = abs(d.x) > 0.001 ? hw / abs(d.x) : .infinity
        let ty = abs(d.y) > 0.001 ? hh / abs(d.y) : .infinity
        let t = min(tx, ty, 1)
        return center + d * t
    }

    static func control(from a: CGPoint, to b: CGPoint, bend: CGFloat) -> CGPoint {
        let mid = (a + b) * 0.5
        let d = b - a
        return CGPoint(x: mid.x - d.y * bend, y: mid.y + d.x * bend)
    }

    /// A small per-link bend so parallel links don't overlap; stable per link id.
    static func bend(for id: UUID) -> CGFloat {
        let h = id.uuid.0 ^ id.uuid.7 ^ id.uuid.13
        return (CGFloat(h % 9) - 4) * 0.018
    }

    static func point(at t: CGFloat, _ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint) -> CGPoint {
        let u = 1 - t
        return p0 * (u * u) + c * (2 * u * t) + p1 * (t * t)
    }

    static func tangent(at t: CGFloat, _ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint) -> CGPoint {
        (c - p0) * (2 * (1 - t)) + (p1 - c) * (2 * t)
    }

    /// Distance from a point to the link curve (sampled) — for tapping thin links.
    static func distance(from p: CGPoint, _ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint) -> CGFloat {
        var best = CGFloat.infinity
        for i in 0...24 {
            best = min(best, point(at: CGFloat(i) / 24, p0, c, p1).distance(to: p))
        }
        return best
    }
}

/// A hand-drawn link: a gentle curve that can draw itself (`progress`) and end in an open arrowhead.
/// `wobble` re-jitters the line a hair each stop-motion frame — a vector "boil", no rasterizing.
nonisolated struct ArrowShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var bend: CGFloat
    var progress: CGFloat = 1
    var head = true
    var wobbleSeed: CGFloat = 0
    var wobbleFrame: Int = 0
    var wobbleAmount: CGFloat = 0.9

    var animatableData: AnimatablePair<AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>, CGFloat> {
        get { AnimatablePair(AnimatablePair(start.animatableData, end.animatableData), progress) }
        set {
            start.animatableData = newValue.first.first
            end.animatableData = newValue.first.second
            progress = newValue.second
        }
    }

    private func jitter(_ salt: CGFloat) -> CGPoint {
        guard wobbleAmount > 0 else { return .zero }
        let f = CGFloat(wobbleFrame)
        return CGPoint(x: sin(wobbleSeed * 12.9 + f * 1.71 + salt) * wobbleAmount,
                       y: cos(wobbleSeed * 7.3 + f * 2.13 + salt) * wobbleAmount)
    }

    func path(in rect: CGRect) -> Path {
        let p0 = start + jitter(0)
        let p1 = end + jitter(3)
        let c = EdgeGeometry.control(from: p0, to: p1, bend: bend) + jitter(5) * 2
        var curve = Path()
        curve.move(to: p0)
        curve.addQuadCurve(to: p1, control: c)
        guard progress < 0.999 || head else { return curve.trimmedPath(from: 0, to: progress) }
        var out = curve.trimmedPath(from: 0, to: max(progress, 0.001))
        guard head, progress > 0.05 else { return out }
        let t = min(progress, 1)
        let tip = EdgeGeometry.point(at: t, p0, c, p1)
        let tangent = EdgeGeometry.tangent(at: t, p0, c, p1)
        let angle = atan2(tangent.y, tangent.x)
        let length: CGFloat = 15
        let spread: CGFloat = .pi / 6.5
        out.move(to: CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)))
        out.addLine(to: tip)
        out.addLine(to: CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
        return out
    }
}

/// One link on the canvas, with its draw-in entrance and coach highlighting.
struct EdgeView: View {
    var edge: MapEdge
    var start: CGPoint
    var end: CGPoint
    var isBackbone: Bool
    var isSelected: Bool
    var isFocused: Bool
    var focusToken: Int
    var wobbleFrame: Int
    var appearDelay: Double = 0
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: ArrowShape {
        ArrowShape(start: start, end: end, bend: EdgeGeometry.bend(for: edge.id), progress: progress,
                   head: edge.isDirected, wobbleSeed: CGFloat(edge.id.uuid.3), wobbleFrame: reduceMotion ? 0 : wobbleFrame,
                   wobbleAmount: reduceMotion ? 0 : 0.8)
    }

    var body: some View {
        ZStack {
            if isFocused {
                shape.stroke(Palette.highlighter, style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                    .opacity(0.85)
                    .transition(.opacity)
            }
            shape.stroke(isSelected ? Palette.accent : Palette.ink.opacity(edge.isDirected ? 0.88 : 0.55),
                         style: StrokeStyle(lineWidth: isBackbone ? 3.4 : 2.2, lineCap: .round, lineJoin: .round,
                                            dash: edge.isDirected ? [] : [7, 6]))
            if !edge.reason.isEmpty && progress > 0.9 {
                let c = EdgeGeometry.control(from: start, to: end, bend: EdgeGeometry.bend(for: edge.id))
                let mid = EdgeGeometry.point(at: 0.5, start, c, end)
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.oliveDeep)
                    .padding(4)
                    .background(Circle().fill(Palette.surface))
                    .position(mid)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(shape.stroke(style: StrokeStyle(lineWidth: 30, lineCap: .round)))
        .pulse(on: isFocused ? focusToken : -1, amount: 1.0)
        .onAppear {
            if reduceMotion { progress = 1; return }
            withAnimation(Motion.draw.delay(appearDelay)) { progress = 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(edge.isDirected ? "Arrow" : "Link without direction"))
        .accessibilityValue(Text(edge.reason))
    }
}
