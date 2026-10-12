import Testing
import CoreGraphics
@testable import ReMap

@MainActor
@Suite("Canvas viewport")
struct CameraTests {
    @Test("Fit keeps complete labels inside the unobscured area", arguments: [
        CGRect(x: 260, y: 140, width: 560, height: 580),
        CGRect(x: 20, y: 290, width: 780, height: 450),
        CGRect(x: 20, y: 240, width: 335, height: 180)
    ])
    func fitLabels(viewport: CGRect) {
        let map = DemoContent.wrongMap(for: DemoContent.headlines())
        let bounds = map.nodes.reduce(CGRect.null) { $0.union(NodeMetrics.frame(for: $1)) }
        var camera = Camera()
        camera.fit(bounds, in: viewport)
        let safeArea = viewport.insetBy(dx: 31, dy: 31)
        for node in map.nodes {
            let frame = NodeMetrics.frame(for: node)
            #expect(safeArea.contains(camera.toScreen(CGPoint(x: frame.minX, y: frame.minY))))
            #expect(safeArea.contains(camera.toScreen(CGPoint(x: frame.maxX, y: frame.maxY))))
        }
        #expect(camera.toScreen(bounds.center).distance(to: viewport.center) < 0.001)
    }

    @Test("A large map fits even below the interactive zoom floor")
    func largeMap() {
        var camera = Camera()
        let bounds = CGRect(x: -5000, y: -4000, width: 12000, height: 9000)
        let viewport = CGRect(x: 20, y: 200, width: 335, height: 240)
        camera.fit(bounds, in: viewport)
        #expect(camera.scale < Camera.minimumScale)
        #expect(viewport.contains(camera.toScreen(bounds.origin)))
        #expect(viewport.contains(camera.toScreen(CGPoint(x: bounds.maxX, y: bounds.maxY))))
        let previousScale = camera.scale
        camera.zoom(by: 1.01, anchor: viewport.center)
        #expect(abs(camera.scale - previousScale * 1.01) < 0.000001)
    }

    @Test("Pinch zoom preserves the world point beneath the fingers")
    func anchoredZoom() {
        var camera = Camera(scale: 0.6, offset: CGSize(width: -900, height: -450))
        let anchor = CGPoint(x: 280, y: 370)
        let world = camera.toWorld(anchor)
        camera.zoom(by: 1.7, anchor: anchor)
        #expect(camera.toScreen(world).distance(to: anchor) < 0.001)
        #expect(camera.toWorld(camera.toScreen(world)).distance(to: world) < 0.001)
    }
}
