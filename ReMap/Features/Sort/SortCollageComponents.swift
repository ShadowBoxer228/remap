import SwiftUI

/// Sort's paper edges are deterministic. They never re-randomize during layout or drag.
nonisolated struct SortPaperCut: Shape {
    var variant: Int = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1)
        let nick: CGFloat = variant.isMultiple(of: 2) ? 1.6 : 2.4
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 5, y: r.minY + 1))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.71, y: r.minY + nick))
        p.addLine(to: CGPoint(x: r.maxX - 4, y: r.minY + 0.5))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 5), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 0.8, y: r.minY + r.height * 0.57))
        p.addLine(to: CGPoint(x: r.maxX - 1, y: r.maxY - 4))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 5, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.43, y: r.maxY - nick))
        p.addLine(to: CGPoint(x: r.minX + 4, y: r.maxY - 0.5))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 5), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + nick * 0.5, y: r.minY + r.height * 0.42))
        p.addLine(to: CGPoint(x: r.minX + 0.5, y: r.minY + 5))
        p.addQuadCurve(to: CGPoint(x: r.minX + 5, y: r.minY + 1), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Printed surfaces use a static texture, never an idle TimelineView or glow.
struct SortPaperSurface: View {
    var tint: Color = Palette.oliveDeep
    var targeted = false
    var available = false
    var variant = 0
    var layered = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let cut = SortPaperCut(variant: variant)
        ZStack {
            if layered {
                cut.fill(Palette.hairline.opacity(scheme == .dark ? 0.65 : 0.48))
                    .offset(x: 2, y: 3)
            }
            cut.fill(Palette.surface)
            if scheme == .light {
                Image("texture_paper")
                    .resizable(resizingMode: .tile)
                    .blendMode(.multiply)
                    .opacity(0.18)
                    .clipShape(cut)
            }
            cut.fill(tint.opacity(targeted ? 0.08 : 0))
            cut.stroke(targeted ? tint : available ? tint.opacity(0.6) : Palette.hairline,
                       lineWidth: targeted ? 2 : contrast == .increased ? 1.5 : 0.75)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct SortRoleHeading: View {
    var role: HeadlineRole
    var count: Int
    var warning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(role.title)
                .font(TypeScale.heading(22))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, role == .backbone ? 7 : 0)
                .background(alignment: .bottom) {
                    if role == .backbone {
                        SortPaperCut(variant: 1)
                            .fill(Palette.butter)
                            .frame(height: 14)
                            .offset(y: 1)
                    }
                }
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(warning ? Palette.accent : Palette.ink2)
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
    }
}

/// Raster artwork stays separate from all interactive and localized content.
struct SortRoleArtwork: View {
    var role: HeadlineRole
    var size: CGFloat = 88
    var arrival: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 1.0

    var body: some View {
        Image("sort_\(role.rawValue)")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .modifier(SortArtworkArrival(progress: progress, reduced: reduceMotion))
            .task(id: arrival) {
                guard arrival != nil else { progress = 1; return }
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { progress = 0 }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .stopMotion(duration: 0.32, fps: 12)) {
                    progress = 1
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

nonisolated private struct SortArtworkArrival: AnimatableModifier {
    var progress: Double
    var reduced: Bool
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let lift = sin(progress * .pi)
        content
            .rotationEffect(.degrees(reduced ? 0 : -3 * lift))
            .offset(y: reduced ? 0 : -3 * lift)
            .scaleEffect(reduced ? 1 : 1 + 0.04 * lift)
            .opacity(0.84 + 0.16 * progress)
    }
}

/// Local appearance only: selection, transfers and persistence remain in SortView.
struct SortHeadlineCard: View {
    var headline: Headline
    var lifted = false
    var maxTextWidth: CGFloat = 280
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var hovered = false

    private var variant: Int { Int(headline.id.uuid.0) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if headline.level == 0 {
                Circle().fill(Palette.ink).frame(width: 6, height: 6)
            } else {
                Circle().strokeBorder(Palette.ink2, lineWidth: 1).frame(width: 6, height: 6)
            }
            Text(headline.text)
                .font(TypeScale.hand(17, weight: headline.level == 0 ? 660 : 480))
                .foregroundStyle(Palette.ink)
                .strikethrough(headline.isFlashcard, color: Palette.ink2)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .frame(maxWidth: maxTextWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let page = headline.page {
                Text("p.\(page)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Palette.ink2)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(minHeight: 46)
        .background {
            SortPaperSurface(targeted: lifted, available: hovered, variant: variant, layered: true)
        }
        .overlay(alignment: .leading) {
            if lifted {
                Rectangle().fill(Palette.oliveDeep).frame(width: 3)
                    .padding(.vertical, 8).padding(.leading, 2)
                    .allowsHitTesting(false)
            }
        }
        .rotationEffect(.degrees(reduceMotion ? 0 : lifted ? -0.8 : 0))
        .offset(y: reduceMotion ? 0 : lifted ? -3 : hovered ? -1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Motion.snappy, value: lifted)
        .animation(reduceMotion ? nil : Motion.snappy, value: hovered)
        .onHover { hovered = $0 }
        .contentShape(Rectangle())
    }
}
