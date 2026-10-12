import SwiftUI

/// Stable, small irregularities: scrolling never changes the shape of a sheet.
nonisolated enum LibraryPaperStyle {
    static func seed(_ id: UUID) -> Double {
        Double(id.uuidString.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) } % 10_000)
    }

    static func columnCount(width: CGFloat, isPortrait: Bool = false) -> Int {
        max(1, min(isPortrait ? 2 : 3, Int((width + 28) / 288)))
    }
}

nonisolated struct LibraryPaperShape: Shape {
    var seed: Double = 1

    func path(in rect: CGRect) -> Path {
        var p = Path()
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
                Image("galata_tower").resizable().scaledToFit()
                    .frame(width: min(250, geometry.size.width * 0.28))
                    .rotationEffect(.degrees(-9))
                    .opacity(0.15)
                    .offset(x: shown ? 100 : 125, y: 70)
                Image("backdrop_istanbul").resizable().scaledToFit()
                    .frame(width: 360).opacity(0.12)
                    .rotationEffect(.degrees(8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: shown ? -220 : -245, y: -70)
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
