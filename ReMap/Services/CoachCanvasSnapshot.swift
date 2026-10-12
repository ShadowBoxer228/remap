import UIKit
import PencilKit

/// A semantic rendering of the complete board, including Pencil ink, labels and directions.
/// This does not capture unrelated app screens or send a continuous stream.
enum CoachCanvasSnapshot {
    static func dataURL(_ map: MindMap) -> String? {
        let drawing = map.sketch.flatMap { try? PKDrawing(data: $0) }
        guard !map.nodes.isEmpty || drawing?.strokes.isEmpty == false else { return nil }
        var bounds = map.nodes.isEmpty ? CGRect.null : map.bounds.insetBy(dx: -150, dy: -70)
        if let drawing, !drawing.strokes.isEmpty { bounds = bounds.union(drawing.bounds.insetBy(dx: -20, dy: -20)) }
        guard !bounds.isNull, !bounds.isInfinite, bounds.width > 0, bounds.height > 0 else { return nil }
        let size = CGSize(width: 1200, height: 850)
        let scale = min((size.width - 40) / bounds.width, (size.height - 40) / bounds.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let data = renderer.jpegData(withCompressionQuality: 0.75) { context in
            UIColor(red: 0.93, green: 0.91, blue: 0.87, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let c = context.cgContext
            c.translateBy(x: 20 + (size.width - 40 - bounds.width * scale) / 2,
                          y: 20 + (size.height - 40 - bounds.height * scale) / 2)
            c.scaleBy(x: scale, y: scale)
            c.translateBy(x: -bounds.minX, y: -bounds.minY)
            c.setStrokeColor(UIColor.darkGray.cgColor); c.setLineWidth(2.5)
            for edge in map.edges {
                guard let from = map.node(edge.from)?.position, let to = map.node(edge.to)?.position else { continue }
                c.move(to: from); c.addLine(to: to); c.strokePath()
                if edge.isDirected {
                    let angle = atan2(to.y - from.y, to.x - from.x)
                    let end = CGPoint(x: to.x - cos(angle) * 60, y: to.y - sin(angle) * 60)
                    c.move(to: CGPoint(x: end.x - cos(angle - 0.5) * 16, y: end.y - sin(angle - 0.5) * 16))
                    c.addLine(to: end)
                    c.addLine(to: CGPoint(x: end.x - cos(angle + 0.5) * 16, y: end.y - sin(angle + 0.5) * 16)); c.strokePath()
                }
            }
            for node in map.nodes {
                let rect = CGRect(x: node.position.x - 120, y: node.position.y - 30, width: 240, height: 60)
                (node.isBackbone ? UIColor(red: 0.95, green: 0.9, blue: 0.65, alpha: 1) : UIColor.white).setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: 16).fill()
                let style = NSMutableParagraphStyle(); style.alignment = .center
                (node.label as NSString).draw(in: rect.insetBy(dx: 8, dy: 8), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: UIColor.black, .paragraphStyle: style])
            }
            if let drawing, !drawing.strokes.isEmpty {
                drawing.image(from: bounds, scale: scale).draw(in: bounds)
            }
        }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }
}
