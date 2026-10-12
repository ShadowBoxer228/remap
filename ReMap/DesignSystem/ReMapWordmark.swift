import SwiftUI

/// The app name as a small printed-paper collage, with one accessible reading.
struct ReMapWordmark: View {
    var size: CGFloat = 36
    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 1

    // Brand artwork grows modestly with Dynamic Type, leaving room for the menu.
    private var em: CGFloat { size * min(typeScale, 1.25) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: em * 0.08) {
            lettering("Re")
                .foregroundStyle(Palette.surface)
                .padding(.horizontal, em * 0.15)
                .padding(.vertical, em * 0.025)
                .background {
                    WordmarkPaper()
                        .fill(Palette.oliveDeep)
                        .overlay {
                            WordmarkGrain().foregroundStyle(Palette.surface.opacity(0.23))
                                .clipShape(WordmarkPaper())
                        }
                }
                .rotationEffect(.degrees(-3))

            lettering("Map")
                .foregroundStyle(Palette.ink)
                .background(alignment: .bottom) {
                    WordmarkPaper()
                        .fill(Palette.butter)
                        .frame(height: em * 0.29)
                        .padding(.horizontal, -em * 0.06)
                        .rotationEffect(.degrees(-2))
                        .offset(y: -em * 0.09)
                }
                .overlay {
                    WordmarkGrain().foregroundStyle(Palette.surface.opacity(0.36))
                        .mask(lettering("Map"))
                }
                .rotationEffect(.degrees(0.6))
        }
        .fixedSize()
        .padding(.vertical, em * 0.10)
        .padding(.horizontal, em * 0.045)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "ReMap"))
        .accessibilityIdentifier("brand.wordmark")
    }

    private func lettering(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: em, weight: .heavy).width(.condensed))
            .tracking(-em * 0.035)
            .lineLimit(1)
    }
}

private nonisolated struct WordmarkPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            .init(x: 0.025, y: 0.035), .init(x: 0.46, y: 0.015),
            .init(x: 0.975, y: 0.045), .init(x: 1, y: 0.49),
            .init(x: 0.972, y: 0.975), .init(x: 0.57, y: 0.985),
            .init(x: 0.015, y: 0.945), .init(x: 0, y: 0.54)
        ]
        return Path { path in
            path.addLines(points.map {
                CGPoint(x: rect.minX + $0.x * rect.width,
                        y: rect.minY + $0.y * rect.height)
            })
            path.closeSubpath()
        }
    }
}

/// Deterministic print specks: no shader, animation clock, or per-frame randomness.
private struct WordmarkGrain: View {
    var body: some View {
        Canvas { context, extent in
            for index in 0..<78 {
                let x = CGFloat((index * 37 + 11) % 101) / 101 * extent.width
                let y = CGFloat((index * 61 + 7) % 103) / 103 * extent.height
                let diameter = max(0.45, extent.height * CGFloat(2 + index % 3) / 175)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter,
                                                    height: diameter * 0.72)),
                             with: .foreground)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
