import SwiftUI

/// "The AI is reading" shimmer that sweeps across placeholder content.
struct Shimmer: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.45)
                            .offset(x: phase * geo.size.width * 1.4)
                            .blendMode(.plusLighter)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View { modifier(Shimmer(active: active)) }

    /// Solid paper card used for content (cards and nodes are content, not glass).
    func paperCard(cornerRadius: CGFloat = 18, elevation: CGFloat = 1) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Palette.surface)
                .shadow(color: .black.opacity(0.05 * elevation), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.07 * elevation), radius: 14 * elevation, y: 6 * elevation)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}

/// Cream paper with a real fiber texture (light mode); plain warm-dark in dark mode.
struct PaperBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Palette.canvas
            .overlay {
                if scheme == .light {
                    Image("texture_paper")
                        .resizable(resizingMode: .tile)
                        .blendMode(.multiply)
                        .opacity(0.55)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The dotted "paper" behind the map; moves with the camera so panning feels physical.
struct DotGrid: View {
    var spacing: CGFloat = 28
    var offset: CGSize = .zero
    var scale: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            let step = max(spacing * scale, 10)
            let r = max(1.1, 1.6 * min(scale, 1.4))
            let ox = offset.width.truncatingRemainder(dividingBy: step)
            let oy = offset.height.truncatingRemainder(dividingBy: step)
            var path = Path()
            var x = ox - step
            while x < size.width + step {
                var y = oy - step
                while y < size.height + step {
                    path.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    y += step
                }
                x += step
            }
            ctx.fill(path, with: .color(Palette.dotGrid))
        }
        .background(PaperBackground())
        .allowsHitTesting(false)
    }
}

/// Small capsule label, e.g. "Backbone".
struct Tag: View {
    var text: String
    var color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Primary call-to-action used across flows.
struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.headline)
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .remapButtonStyle(prominent: true)
        .tint(Palette.ink)
    }
}
