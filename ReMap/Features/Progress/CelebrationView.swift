import SwiftUI

/// A brief Galata celebration after every structural question has been resolved.
struct CelebrationView: View {
    var trigger: Int
    @State private var visible = false
    @State private var startDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            if visible {
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        Confetti(elapsed: context.date.timeIntervalSince(startDate))
                    }
                    .ignoresSafeArea()
                }
                VStack(spacing: 12) {
                    Image("galata_tower")
                        .resizable()
                        .scaledToFit()
                        .frame(height: min(260, geometry.size.height * 0.38))
                        .boil(0.8, fps: 8)
                    Text("Backbone complete.")
                        .font(TypeScale.display(min(48, geometry.size.width * 0.085)))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text("Details can wait for your next sitting.")
                        .font(TypeScale.hand(20))
                        .foregroundStyle(Palette.ink2)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: min(620, geometry.size.width - 24))
                .background(
                    GrainBlob(color: Palette.butter, seed: 9, wobble: 0.06)
                )
                .transition(.asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity),
                                        removal: .scale(scale: 1.1).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            startDate = Date()
            withAnimation(.stopMotion(duration: 0.5, fps: 12)) { visible = true }
            Task {
                try? await Task.sleep(for: .seconds(2.8))
                withAnimation(.easeIn(duration: 0.35)) { visible = false }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(visible ? "Backbone complete" : ""))
    }
}

/// Grainy paper confetti in the collage palette, falling with a little flutter.
private struct Confetti: View {
    var elapsed: TimeInterval

    var body: some View {
        Canvas { ctx, size in
            let colors = [Palette.olive, Palette.butter, Palette.ink, Palette.oliveDeep, Palette.highlighter]
            for i in 0..<90 {
                let seed = Double(i) * 12.9898
                let rx = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                let x0 = abs(rx) * size.width
                let speed = 160 + abs(sin(seed * 3.1)) * 220
                let delay = abs(cos(seed)) * 0.6
                let t = max(0, elapsed - delay)
                let y = -40 + t * speed
                guard y < size.height + 40 else { continue }
                let x = x0 + sin(t * 3 + seed) * 40
                let w: CGFloat = i % 3 == 0 ? 14 : 9
                var item = ctx
                item.translateBy(x: x, y: y)
                item.rotate(by: .radians(t * (2 + Double(i % 5)) + seed))
                let rect = CGRect(x: -w / 2, y: -w / 2, width: w, height: i % 4 == 0 ? w * 0.45 : w)
                let shape = i % 2 == 0 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2)
                item.fill(shape, with: .color(colors[i % colors.count]))
            }
        }
        .grain(0.12)
    }
}
