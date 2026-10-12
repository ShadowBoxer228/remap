import SwiftUI

/// Reveals glyphs one by one with a soft fade-and-rise, like the coach writing in real time.
@available(iOS 18.0, *)
nonisolated struct RevealRenderer: TextRenderer, Animatable {
    var shown: Double
    var softness: Double = 6

    var animatableData: Double {
        get { shown }
        set { shown = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var index = 0.0
        for line in layout {
            for run in line {
                for slice in run {
                    let t = min(max((shown - index) / softness, 0), 1)
                    index += 1
                    if t >= 1 { ctx.draw(slice); continue }
                    if t <= 0 { continue }
                    var copy = ctx
                    copy.opacity = t
                    copy.translateBy(x: 0, y: (1 - t) * 5)
                    copy.draw(slice)
                }
            }
        }
    }
}

/// Coach text that streams in. Supports *markdown* emphasis.
struct StreamingText: View {
    var text: String
    var font: Font = TypeScale.coach()
    var color: Color = Palette.ink
    var charactersPerSecond: Double = 60
    var onFinished: () -> Void = {}
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                styledText.textRenderer(RevealRenderer(shown: reduceMotion ? 10_000 : shown))
            } else {
                ReMapLegacyStreamingText(text: attributed, color: color,
                                        shown: reduceMotion ? 10_000 : shown)
                    .font(font)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: start)
        .onChange(of: text) { _, _ in
            shown = 0
            start()
        }
    }

    private var styledText: some View {
        Text(attributed)
            .font(font)
            .foregroundStyle(color)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func start() {
        let count = Double(text.count)
        let duration = max(0.35, count / charactersPerSecond)
        withAnimation(.linear(duration: duration)) {
            shown = count + 8
        } completion: {
            onFinished()
        }
    }
}

/// A coach note with quick replies — used outside the canvas (Collect, Sort).
struct CoachNote: View {
    var text: String
    var replies: [String] = []
    var onReply: (String) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CoachAvatar(size: 46)
            VStack(alignment: .leading, spacing: 12) {
                StreamingText(text: text, font: TypeScale.coach(19))
                if !replies.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(replies, id: \.self) { reply in
                            Button(reply) { onReply(reply) }
                                .remapButtonStyle()
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .transition(RiseIn())
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.butter.opacity(0.85))
        )
        .grain(0.05)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .id(text)
        .transition(RiseIn())
    }
}

/// The coach's face: the halftone pencil cutout over a grainy blob.
struct CoachAvatar: View {
    var size: CGFloat = 44
    var speaking = false

    var body: some View {
        ZStack {
            GrainBlob(color: Palette.olive, seed: 7, wobble: speaking ? 0.14 : 0.08)
            Image("coach_pencil")
                .resizable()
                .scaledToFit()
                .padding(size * 0.12)
                .boil(0.6, fps: 6, active: speaking)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Wraps children onto multiple lines.
nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += lineHeight + spacing; lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineHeight + spacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
