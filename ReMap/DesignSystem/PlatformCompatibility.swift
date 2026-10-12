import SwiftUI
import UIKit

/// Keeps modern system styling while supporting the same controls on iPadOS 17.
struct ReMapGlassContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

extension View {
    @ViewBuilder
    func remapButtonStyle(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
    }

    @ViewBuilder
    func remapGlass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func remapFormPresentation() -> some View {
        if #available(iOS 18.0, *) { presentationSizing(.form) }
        else { self }
    }

    @ViewBuilder
    func remapChatAlignment(scrollToLatest: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) { defaultScrollAnchor(.top, for: .alignment) }
        else { defaultScrollAnchor(.top).onAppear(perform: scrollToLatest) }
    }

    @ViewBuilder
    func remapTwoFingerPan(_ action: @escaping (CGSize) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            gesture(TwoFingerPan(onPan: action))
        } else {
            background(LegacyCanvasPan(onPan: action))
        }
    }
}

/// Observes touches over the canvas without covering its nodes or Pencil layer.
private struct LegacyCanvasPan: UIViewRepresentable {
    var onPan: (CGSize) -> Void

    func makeUIView(context: Context) -> PanObservationView {
        let view = PanObservationView()
        view.onPan = onPan
        return view
    }

    func updateUIView(_ view: PanObservationView, context: Context) { view.onPan = onPan }

    static func dismantleUIView(_ view: PanObservationView, coordinator: ()) {
        view.detach()
    }

    final class PanObservationView: UIView, UIGestureRecognizerDelegate {
        var onPan: (CGSize) -> Void = { _ in }
        private weak var attachedWindow: UIWindow?
        private lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
            recognizer.minimumNumberOfTouches = 2
            recognizer.maximumNumberOfTouches = 2
            recognizer.allowedScrollTypesMask = .all
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            if let window {
                window.addGestureRecognizer(pan)
                attachedWindow = window
            }
        }

        func detach() {
            attachedWindow?.removeGestureRecognizer(pan)
            attachedWindow = nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            window != nil && bounds.contains(gestureRecognizer.location(in: self))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func moved(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else { return }
            let delta = recognizer.translation(in: self)
            recognizer.setTranslation(.zero, in: self)
            onPan(CGSize(width: delta.x, height: delta.y))
        }
    }
}

/// The animated contour stays identical; older systems use the same palette.
struct ReMapMeshGradient: View {
    var width: Int
    var height: Int
    var points: [SIMD2<Float>]
    var colors: [Color]

    var body: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(width: width, height: height, points: points, colors: colors)
        } else {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// Reveals characters without changing text layout on systems before TextRenderer.
struct ReMapLegacyStreamingText: View, Animatable {
    var text: AttributedString
    var color: Color
    var shown: Double

    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    var body: some View { Text(revealed) }

    private var revealed: AttributedString {
        var result = text
        var index = result.startIndex
        var offset = 0.0
        while index < result.endIndex {
            let next = result.characters.index(after: index)
            result[index..<next].foregroundColor = color.opacity(min(1, max(0, (shown - offset) / 6)))
            index = next
            offset += 1
        }
        return result
    }
}
