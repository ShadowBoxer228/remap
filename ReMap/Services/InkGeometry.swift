import Foundation
import CoreGraphics
import PencilKit

/// Reads Pencil ink against the map: which strokes are arrows between topics, and what the
/// remaining marks point at. Ink and nodes share world coordinates (SketchLayer drives the camera).
nonisolated enum InkGeometry {
    /// How far outside a topic's frame a stroke end still counts as touching it.
    static let reach: CGFloat = 24

    struct Mark: Encodable, Equatable, Sendable {
        enum Kind: String, Encodable, Sendable { case arrow, circle, mark }
        let kind: Kind
        /// Topics the mark touches or encloses.
        var nodeIDs: [UUID]
        var from: UUID? = nil
        var to: UUID? = nil
        let x: Int
        let y: Int
    }

    static func points(of stroke: PKStroke) -> [CGPoint] {
        stroke.path.interpolatedPoints(by: .distance(8)).map { $0.location.applying(stroke.transform) }
    }

    /// The topic under a point, preferring the closest centre when frames overlap.
    static func node(at point: CGPoint, in nodes: [MapNode]) -> MapNode? {
        nodes.filter { NodeMetrics.frame(for: $0).insetBy(dx: -reach, dy: -reach).contains(point) }
            .min { $0.position.distance(to: point) < $1.position.distance(to: point) }
    }

    /// A stroke that starts on one topic and ends on another, without wandering off, is a connection.
    static func connection(for points: [CGPoint], in nodes: [MapNode]) -> (from: UUID, to: UUID)? {
        guard let start = points.first, let end = points.last, !isClosed(points),
              let a = node(at: start, in: nodes), let b = node(at: end, in: nodes), a.id != b.id else { return nil }
        let chord = start.distance(to: end)
        // A hooked arrowhead drawn in the same stroke adds length; a scribble adds far more.
        guard chord >= 40, length(of: points) <= chord * 2.5 + 120 else { return nil }
        return (a.id, b.id)
    }

    /// A short stroke right at the topic an arrow just reached is that arrow's head.
    static func isArrowhead(_ points: [CGPoint], at target: MapNode) -> Bool {
        let box = bounds(of: points)
        return max(box.width, box.height) <= 70
            && NodeMetrics.frame(for: target).insetBy(dx: -reach - 40, dy: -reach - 40).intersects(box)
    }

    /// The topic the last ink arrow reached, so a separately drawn arrowhead can be absorbed too.
    struct ArrowTarget: Equatable, Sendable {
        var nodeID: UUID
        var time: Date
    }

    enum Absorption: Equatable, Sendable {
        case connect(from: UUID, to: UUID)
        case arrowhead
        case keep
    }

    /// Decides, stroke by stroke in drawing order, which new ink becomes a connection, which is
    /// that connection's head (within 2.5 s at the target topic) and which stays as ink.
    static func absorb(_ strokes: [[CGPoint]], nodes: [MapNode], target: inout ArrowTarget?, now: Date = .now) -> [Absorption] {
        strokes.map { points in
            if let link = connection(for: points, in: nodes) {
                target = ArrowTarget(nodeID: link.to, time: now)
                return .connect(from: link.from, to: link.to)
            }
            if let current = target, now.timeIntervalSince(current.time) < 2.5,
               let node = nodes.first(where: { $0.id == current.nodeID }), isArrowhead(points, at: node) {
                return .arrowhead
            }
            target = nil
            return .keep
        }
    }

    static func marks(in drawing: PKDrawing, nodes: [MapNode], limit: Int = 20) -> [Mark] {
        let all = drawing.strokes.map { mark(for: points(of: $0), nodes: nodes) }
        // Circles and arrows say the most about the learner's thinking; keep them when trimming.
        let ranked = all.filter { $0.kind != .mark } + all.filter { $0.kind == .mark && !$0.nodeIDs.isEmpty }
        return Array(ranked.prefix(limit))
    }

    static func mark(for points: [CGPoint], nodes: [MapNode]) -> Mark {
        let box = bounds(of: points)
        let x = box.isNull ? 0 : Int(box.midX.rounded()), y = box.isNull ? 0 : Int(box.midY.rounded())
        if isClosed(points) {
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            let inside = nodes.filter { path.contains($0.position) }.map(\.id)
            if !inside.isEmpty { return Mark(kind: .circle, nodeIDs: inside, x: x, y: y) }
        }
        if let start = points.first, let end = points.last,
           let a = node(at: start, in: nodes), let b = node(at: end, in: nodes), a.id != b.id {
            return Mark(kind: .arrow, nodeIDs: [a.id, b.id], from: a.id, to: b.id, x: x, y: y)
        }
        let center = CGPoint(x: x, y: y)
        let nearest = nodes.filter { $0.position.distance(to: center) <= 160 }
            .min { $0.position.distance(to: center) < $1.position.distance(to: center) }
        return Mark(kind: .mark, nodeIDs: nearest.map { [$0.id] } ?? [], x: x, y: y)
    }

    static func isClosed(_ points: [CGPoint]) -> Bool {
        guard let start = points.first, let end = points.last, points.count > 4 else { return false }
        let box = bounds(of: points)
        let gap = start.distance(to: end)
        return length(of: points) >= 150 && gap <= max(40, 0.2 * hypot(box.width, box.height))
    }

    static func length(of points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    static func bounds(of points: [CGPoint]) -> CGRect {
        points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}
