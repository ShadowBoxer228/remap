import SwiftUI
import PencilKit

enum PenMode: Equatable {
    case off
    /// Freehand doodles and "memory landmarks", saved with the map.
    case sketch
    /// Write a word with Apple Pencil — it becomes a node where you wrote it (iOS 27).
    case handwrite

    static var handwritingAvailable: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }
}

/// PencilKit over the map. The canvas drives the camera while active (its scroll view zooms and pans),
/// so ink stays crisp at any zoom and stays aligned with the nodes underneath.
struct SketchLayer: UIViewRepresentable {
    @Bindable var model: SessionModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = .default
        #endif
        canvas.contentSize = CanvasScreen.worldSize
        canvas.minimumZoomScale = min(Camera.minimumScale, model.camera.scale)
        canvas.maximumZoomScale = Camera.maximumScale
        canvas.contentInset = UIEdgeInsets(top: 3000, left: 3000, bottom: 3000, right: 3000)
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.bouncesZoom = false
        canvas.delegate = context.coordinator
        context.coordinator.canvas = canvas
        context.coordinator.configure(for: model.penMode)
        context.coordinator.syncFromCamera()

        let picker = PKToolPicker()
        picker.addObserver(canvas)
        picker.setVisible(true, forFirstResponder: canvas)
        context.coordinator.picker = picker
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.model = model
        if context.coordinator.mode != model.penMode { context.coordinator.configure(for: model.penMode) }
        context.coordinator.syncFromCamera()
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.picker?.setVisible(false, forFirstResponder: canvas)
        coordinator.flushHandwriting()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var model: SessionModel
        weak var canvas: PKCanvasView?
        var picker: PKToolPicker?
        var mode: PenMode = .off
        private var syncing = false
        private var pendingStrokeIDs: Set<UUID> = []
        private var convertTask: Task<Void, Never>?

        init(model: SessionModel) { self.model = model }

        func configure(for mode: PenMode) {
            guard let canvas else { return }
            flushHandwriting()
            self.mode = mode
            switch mode {
            case .sketch:
                canvas.drawing = model.map.sketch.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
                canvas.tool = PKInkingTool(.pen, color: UIColor(hex: 0x2B2E26), width: 3)
            case .handwrite, .off:
                canvas.drawing = PKDrawing()
                canvas.tool = PKInkingTool(.monoline, color: UIColor(hex: 0x6F7040), width: 4)
            }
        }

        /// Camera → scroll view.
        func syncFromCamera() {
            guard let canvas, !syncing else { return }
            let camera = model.camera
            syncing = true
            canvas.minimumZoomScale = min(Camera.minimumScale, camera.scale)
            if abs(canvas.zoomScale - camera.scale) > 0.0001 { canvas.zoomScale = camera.scale }
            let target = CGPoint(x: -camera.offset.width, y: -camera.offset.height)
            if canvas.contentOffset.distance(to: target) > 0.5 { canvas.contentOffset = target }
            syncing = false
        }

        /// Scroll view → camera (the user panned or pinched on the ink layer).
        private func syncToCamera(_ scrollView: UIScrollView) {
            guard !syncing else { return }
            syncing = true
            model.camera.scale = scrollView.zoomScale
            model.camera.offset = CGSize(width: -scrollView.contentOffset.x, height: -scrollView.contentOffset.y)
            syncing = false
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { syncToCamera(scrollView) }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { syncToCamera(scrollView) }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            switch mode {
            case .sketch:
                let drawing = canvasView.drawing
                model.saveSketch(drawing.strokes.isEmpty ? nil : drawing.dataRepresentation())
            case .handwrite:
                scheduleConversion(canvasView.drawing)
            case .off:
                break
            }
        }

        // MARK: Handwriting → node

        private func scheduleConversion(_ drawing: PKDrawing) {
            guard #available(iOS 27.0, *) else { return }
            for stroke in drawing.strokes { pendingStrokeIDs.insert(stroke.id) }
            convertTask?.cancel()
            convertTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1100))
                guard !Task.isCancelled else { return }
                await self?.convert()
            }
        }

        func flushHandwriting() {
            convertTask?.cancel()
            pendingStrokeIDs = []
        }

        @available(iOS 27.0, *)
        private func convert() async {
            guard let canvas else { return }
            let drawing = canvas.drawing
            let ids = pendingStrokeIDs.intersection(Set(drawing.strokes.map(\.id)))
            guard !ids.isEmpty else { return }
            let recognizer = PKStrokeRecognizer()
            await recognizer.updateDrawing(drawing)
            let text = await recognizer.recognizedText(strokeIDs: ids)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let strokes = drawing.strokes.filter { ids.contains($0.id) }
            let bounds = strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
            pendingStrokeIDs.subtract(ids)
            guard !text.isEmpty, !bounds.isNull else { return }
            // The ink "becomes" the node: remove it and spawn the node from where it was written.
            var remaining = canvas.drawing
            remaining.strokes.removeAll { ids.contains($0.id) }
            canvas.drawing = remaining
            let label = text.replacingOccurrences(of: "\n", with: " ")
            withAnimation(Motion.spawn) {
                let id = model.addNode(label, at: bounds.center, backbone: model.session.phase == .backbone && model.map.nodes.count < 4)
                model.selection = .node(id)
            }
        }
    }
}

/// The saved freehand layer, drawn as an image under the nodes when the pen is off.
struct SketchImage: View {
    var data: Data?
    @State private var rendered: (image: UIImage, frame: CGRect)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let rendered {
                Image(uiImage: rendered.image)
                    .resizable()
                    .frame(width: rendered.frame.width, height: rendered.frame.height)
                    .offset(x: rendered.frame.minX, y: rendered.frame.minY)
            }
        }
        .allowsHitTesting(false)
        .task(id: data) {
            guard let data, let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty else { rendered = nil; return }
            let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
            let image = drawing.image(from: bounds, scale: 2)
            rendered = (image, bounds)
        }
    }
}
