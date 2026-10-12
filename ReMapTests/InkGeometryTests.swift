import Foundation
import PencilKit
import Testing
@testable import ReMap

@Suite("Pencil ink against the map")
struct InkGeometryTests {
    private let a = MapNode(label: "First", position: .zero)
    private let b = MapNode(label: "Second", position: CGPoint(x: 300, y: 0))
    private let c = MapNode(label: "Third", position: CGPoint(x: 150, y: 400))
    private var nodes: [MapNode] { [a, b, c] }

    private func line(_ from: CGPoint, _ to: CGPoint, steps: Int = 20) -> [CGPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }

    private func loop(around center: CGPoint, radius: CGSize) -> [CGPoint] {
        (0...36).map { i in
            let angle = CGFloat(i) / 36 * 2 * .pi
            return CGPoint(x: center.x + cos(angle) * radius.width, y: center.y + sin(angle) * radius.height)
        }
    }

    private func stroke(_ points: [CGPoint]) -> PKStroke {
        let path = PKStrokePath(controlPoints: points.enumerated().map {
            PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.01, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }

    @Test("A stroke from one topic to another is a directed connection")
    func arrowConnects() throws {
        let points = InkGeometry.points(of: stroke(line(a.position, b.position)))
        let link = try #require(InkGeometry.connection(for: points, in: nodes))
        #expect(link.from == a.id && link.to == b.id)
    }

    @Test("Drawing the other way round reverses the direction")
    func reversed() throws {
        let link = try #require(InkGeometry.connection(for: line(b.position, a.position), in: nodes))
        #expect(link.from == b.id && link.to == a.id)
    }

    @Test("A stroke may start or end just outside a topic's frame")
    func reachOutsideFrame() throws {
        let link = InkGeometry.connection(for: line(CGPoint(x: 60, y: 20), CGPoint(x: 240, y: -20)), in: nodes)
        #expect(link?.from == a.id && link?.to == b.id)
    }

    @Test("Scribbles inside one topic, loops and strokes into empty space are not connections")
    func nonArrows() {
        #expect(InkGeometry.connection(for: line(CGPoint(x: -20, y: 0), CGPoint(x: 20, y: 5)), in: nodes) == nil)
        #expect(InkGeometry.connection(for: line(a.position, CGPoint(x: 150, y: -300)), in: nodes) == nil)
        #expect(InkGeometry.connection(for: loop(around: CGPoint(x: 150, y: 0), radius: CGSize(width: 220, height: 80)), in: nodes) == nil)
        // Starts on A, ends on B, but wanders far away first.
        let detour = line(a.position, CGPoint(x: 0, y: 900)) + line(CGPoint(x: 0, y: 900), CGPoint(x: 900, y: 900))
            + line(CGPoint(x: 900, y: 900), b.position)
        #expect(InkGeometry.connection(for: detour, in: nodes) == nil)
    }

    @Test("A small tick at the target is the arrowhead; a stroke elsewhere is not")
    func arrowhead() {
        #expect(InkGeometry.isArrowhead(line(CGPoint(x: 230, y: -30), CGPoint(x: 260, y: 0)), at: b))
        #expect(!InkGeometry.isArrowhead(line(CGPoint(x: 130, y: 380), CGPoint(x: 160, y: 400)), at: b))
        #expect(!InkGeometry.isArrowhead(line(CGPoint(x: 200, y: 0), CGPoint(x: 400, y: 200)), at: b))
    }

    @Test("Circling two topics is reported with both topics")
    func circle() {
        let mark = InkGeometry.mark(for: loop(around: CGPoint(x: 150, y: 0), radius: CGSize(width: 260, height: 90)), nodes: nodes)
        #expect(mark.kind == .circle)
        #expect(Set(mark.nodeIDs) == [a.id, b.id])
    }

    @Test("Loose marks name the nearest topic, or none when far away")
    func looseMarks() {
        let near = InkGeometry.mark(for: line(CGPoint(x: 120, y: 360), CGPoint(x: 140, y: 340)), nodes: nodes)
        #expect(near.kind == .mark && near.nodeIDs == [c.id])
        let far = InkGeometry.mark(for: line(CGPoint(x: 2000, y: 2000), CGPoint(x: 2030, y: 2010)), nodes: nodes)
        #expect(far.kind == .mark && far.nodeIDs.isEmpty)
    }

    @Test("Board ink summary keeps meaningful marks first and respects the limit")
    func summary() {
        var strokes = (0..<30).map { i in stroke(line(CGPoint(x: 140, y: 380 + i), CGPoint(x: 150, y: 390 + i))) }
        strokes.append(stroke(loop(around: CGPoint(x: 150, y: 0), radius: CGSize(width: 260, height: 90))))
        strokes.append(stroke(line(CGPoint(x: 5000, y: 5000), CGPoint(x: 5010, y: 5000))))
        let marks = InkGeometry.marks(in: PKDrawing(strokes: strokes), nodes: nodes)
        #expect(marks.count == 20)
        #expect(marks.first?.kind == .circle)
        #expect(marks.allSatisfy { !$0.nodeIDs.isEmpty })
    }
}
