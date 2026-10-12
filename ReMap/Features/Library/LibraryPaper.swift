import SwiftUI

/// Stable, small irregularities: scrolling never changes the shape of a sheet.
nonisolated enum LibraryPaperStyle {
    static func seed(_ id: UUID) -> Double {
        Double(id.uuidString.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) } % 10_000)
    }

    static func columnCount(width: CGFloat, isPortrait: Bool = false) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        return max(1, min(isPortrait ? 2 : 3, Int(min(width, 10_000) + 28) / 288))
    }
}

nonisolated struct LibraryPaperShape: Shape {
    var seed: Double = 1

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { return p }
        let inset: CGFloat = 4
        let r = rect.insetBy(dx: inset, dy: inset)
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        p.move(to: corners[0])
        for edge in 0..<4 {
            let a = corners[edge], b = corners[(edge + 1) % 4]
            let count = max(8, Int(hypot(b.x - a.x, b.y - a.y) / 15))
            for step in 1...count {
                let t = CGFloat(step) / CGFloat(count)
                let n = CGFloat(sin(Double(step) * 2.31 + seed + Double(edge) * 7.7)) * 1.45
                let vertical = edge % 2 == 1
                p.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t + (vertical ? n : 0),
                                     y: a.y + (b.y - a.y) * t + (vertical ? 0 : n)))
            }
        }
        p.closeSubpath()
        return p
    }
}

struct LibraryPaperSurface: View {
    var seed: Double
    var color: Color = Palette.surface

    var body: some View {
        ZStack {
            LibraryPaperShape(seed: seed + 9)
                .fill(Palette.olive.opacity(0.22))
                .rotationEffect(.degrees(-0.8))
                .offset(x: 3, y: 5)
            LibraryPaperShape(seed: seed)
                .fill(color)
                .overlay {
                    Image("texture_paper").resizable(resizingMode: .tile)
                        .blendMode(.multiply).opacity(0.17)
                        .clipShape(LibraryPaperShape(seed: seed))
                }
                .shadow(color: Palette.ink.opacity(0.10), radius: 1, x: 0, y: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct LibraryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

struct LibraryEntrance: ViewModifier {
    var index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) :
                    .stopMotion(duration: 0.35, fps: 12).delay(Double(min(index, 6)) * 0.045)) {
                    shown = true
                }
            }
    }
}

struct LibraryBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                PaperBackground()
                LibraryStudyFragment(isMap: true)
                    .frame(width: 350, height: 270)
                    .rotationEffect(.degrees(-11))
                    .opacity(0.38)
                    .offset(x: shown || reduceMotion ? 132 : 157, y: 88)
                LibraryStudyFragment(isMap: false)
                    .frame(width: 280, height: 230)
                    .opacity(0.30)
                    .rotationEffect(.degrees(13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: shown || reduceMotion ? -172 : -197, y: -112)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(reduceMotion ? nil : .stopMotion(duration: 0.5, fps: 10)) { shown = true }
        }
    }
}

/// Quiet remnants of studying at the page edges, drawn once without an animation clock.
private struct LibraryStudyFragment: View {
    var isMap: Bool

    var body: some View {
        ZStack {
            LibraryPaperShape(seed: isMap ? 31 : 47)
                .fill(Palette.surface)
                .shadow(color: Palette.ink.opacity(0.08), radius: 1, x: 0, y: 2)
            Canvas { context, size in
                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    CGPoint(x: x * size.width, y: y * size.height)
                }
                let pencil = GraphicsContext.Shading.color(Palette.ink2.opacity(0.65))
                let stroke = StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                if isMap {
                    let centers = [point(0.22, 0.30), point(0.62, 0.23),
                                   point(0.47, 0.61), point(0.81, 0.76)]
                    for (from, to) in [(0, 1), (0, 2), (1, 2), (2, 3)] {
                        var line = Path()
                        line.move(to: centers[from])
                        let a = centers[from], b = centers[to]
                        line.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2 - 12,
                                                                  y: (a.y + b.y) / 2 + 14))
                        context.stroke(line, with: pencil, style: stroke)
                    }
                    for (index, center) in centers.enumerated() {
                        let rect = CGRect(x: center.x - 34, y: center.y - 18, width: 68, height: 36)
                        let paper = LibraryPaperShape(seed: Double(index + 20)).path(in: rect)
                        context.fill(paper, with: .color(index == 0 ? Palette.butter : Palette.surface))
                        context.stroke(paper, with: pencil, style: stroke)
                        var marks = Path()
                        marks.move(to: CGPoint(x: rect.minX + 13, y: rect.midY - 4))
                        marks.addLine(to: CGPoint(x: rect.maxX - 12, y: rect.midY - 5))
                        marks.move(to: CGPoint(x: rect.minX + 13, y: rect.midY + 5))
                        marks.addLine(to: CGPoint(x: rect.maxX - 22, y: rect.midY + 4))
                        context.stroke(marks, with: pencil, style: stroke)
                    }
                } else {
                    let highlight = CGRect(x: size.width * 0.16, y: size.height * 0.21,
                                           width: size.width * 0.55, height: 18)
                    context.fill(LibraryPaperShape(seed: 8).path(in: highlight), with: .color(Palette.butter))
                    for row in 0..<4 {
                        let y = 0.26 + CGFloat(row) * 0.15
                        var line = Path()
                        line.move(to: point(0.19, y))
                        line.addQuadCurve(to: point(row == 3 ? 0.55 : 0.78, y - 0.012),
                                          control: point(0.43, y + 0.008))
                        context.stroke(line, with: pencil, style: stroke)
                    }
                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: size.width * 0.63, y: size.height * 0.66,
                                                 width: 47, height: 32))
                    context.stroke(circle, with: .color(Palette.oliveDeep.opacity(0.65)), style: stroke)
                }
            }
            Image("texture_paper").resizable(resizingMode: .tile)
                .blendMode(.multiply).opacity(0.15)
                .clipShape(LibraryPaperShape(seed: isMap ? 31 : 47))
        }
    }
}
