import SwiftUI

/// Unplaced topics live directly on the paper's left edge, without a panel or disclosure.
struct CanvasTopicRail: View {
    @Bindable var model: SessionModel
    var maxHeight: CGFloat
    var onPlace: (Headline) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let items = model.session.unplacedHeadlines
        if !items.isEmpty {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { headline in
                        topic(headline)
                            .transition(cardTransition)
                    }
                }
                .padding(4)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(0, maxHeight), max(56, contentHeight)), alignment: .top)
            .animation(reduceMotion ? .easeOut(duration: 0.14) : .smooth(duration: 0.24), value: items.map(\.id))
            .accessibilityIdentifier("canvas-topic-rail")
        }
    }

    private func topic(_ headline: Headline) -> some View {
        Button {
            onPlace(headline)
        } label: {
            CanvasTopicSlip(headline: headline)
        }
        .buttonStyle(CanvasTopicPressStyle())
        .draggable(headline.id.uuidString) {
            CanvasTopicSlip(headline: headline, lifted: true)
                .frame(width: 196)
                .padding(4)
        }
        .contextMenu {
            Button(String(localized: "Put it on the paper"), systemImage: "plus.circle") { onPlace(headline) }
            Button(String(localized: "Where does it go?"), systemImage: "questionmark.circle") { suggest(headline) }
        }
        .accessibilityLabel(Text(headline.text))
        .accessibilityValue(Text(headline.role?.title ?? ""))
        .accessibilityHint(Text("Drag onto the map, or double-tap to place."))
        .accessibilityAction(named: Text("Where does it go?")) { suggest(headline) }
        .accessibilityIdentifier("canvas-topic-\(headline.id.uuidString)")
    }

    private func suggest(_ headline: Headline) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.14) : Motion.snappy) {
            model.startPlacement(label: headline.text, headlineID: headline.id)
        }
    }

    private var cardTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: -8).combined(with: .opacity).animation(.smooth(duration: 0.24)),
            removal: .offset(x: 10).combined(with: .opacity).animation(.easeOut(duration: 0.14))
        )
    }
}

/// The drag preview keeps the same type, paper and role mark as its source card.
struct CanvasTopicSlip: View {
    var headline: Headline
    var lifted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false

    private var roleMark: String {
        switch headline.role {
        case .backbone: "star.fill"
        case .topic: "circle.fill"
        case .detail: "minus"
        case nil: "circle"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: roleMark)
                .font(.system(size: headline.role == .backbone ? 10 : 8, weight: .semibold))
                .foregroundStyle(Palette.oliveDeep)
                .frame(width: 10)
                .accessibilityHidden(true)
            Text(headline.text)
                .font(TypeScale.hand(16, weight: headline.role == .backbone ? 640 : 480))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 48, alignment: .leading)
        .background {
            CanvasTopicPaper()
                .fill(headline.role == .backbone ? Palette.butter : Palette.surface)
                .shadow(color: Palette.ink.opacity(lifted ? 0.14 : 0.06), radius: lifted ? 4 : 1, x: 0, y: lifted ? 3 : 1)
        }
        .overlay {
            CanvasTopicPaper()
                .stroke(contrast == .increased ? Palette.ink2 : Palette.hairline,
                        lineWidth: contrast == .increased ? 1.5 : 0.6)
                .allowsHitTesting(false)
        }
        .contentShape(.interaction, RoundedRectangle(cornerRadius: 8))
        .contentShape(.dragPreview, CanvasTopicPaper())
        .scaleEffect(reduceMotion ? 1 : lifted ? 1.035 : 1)
        .offset(y: !reduceMotion && hovered ? -1 : 0)
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: hovered)
        .onHover { hovered = $0 }
    }
}

/// Tiny, stable cut-paper irregularities; no per-frame grain or idle animation.
nonisolated private struct CanvasTopicPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1)
        var path = Path()
        path.move(to: CGPoint(x: r.minX + 6, y: r.minY + 0.5))
        path.addLine(to: CGPoint(x: r.midX, y: r.minY + 1.2))
        path.addLine(to: CGPoint(x: r.maxX - 5, y: r.minY))
        path.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 5), control: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - 0.6, y: r.maxY - 5))
        path.addQuadCurve(to: CGPoint(x: r.maxX - 5, y: r.maxY - 0.5), control: CGPoint(x: r.maxX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.midX * 0.8, y: r.maxY - 1))
        path.addLine(to: CGPoint(x: r.minX + 5, y: r.maxY))
        path.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 5), control: CGPoint(x: r.minX, y: r.maxY))
        path.addLine(to: CGPoint(x: r.minX + 0.5, y: r.minY + 5))
        path.addQuadCurve(to: CGPoint(x: r.minX + 6, y: r.minY + 0.5), control: CGPoint(x: r.minX, y: r.minY))
        path.closeSubpath()
        return path
    }
}

private struct CanvasTopicPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.18), value: configuration.isPressed)
    }
}
