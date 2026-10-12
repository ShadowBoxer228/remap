import SwiftUI

/// Four collage pages that explain the philosophy: effort stays, friction goes.
struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let title: String
        let body: String
        let art: String
    }

    private let pages = [
        Page(title: String(localized: "Copying isn't learning."),
             body: String(localized: "Pages of beautiful notes feel productive. But learning happens in the gap between reading and writing — when your brain has to decide what matters."),
             art: "onboarding_linear_notes"),
        Page(title: String(localized: "Backbone first. Details later."),
             body: String(localized: "Collect the headlines, judge what carries the topic, draw that skeleton. Your map keeps growing over several sittings — like your understanding."),
             art: "onboarding_map_sheet"),
        Page(title: String(localized: "It asks. You think."),
             body: String(localized: "ReMap never draws your map for you. It questions your arrows, your groups and your hubs — out loud if you like — so the understanding stays yours."),
             art: "onboarding_thought_cloud"),
        Page(title: String(localized: "Effort stays. Friction goes."),
             body: String(localized: "Write with Apple Pencil, drag ideas around, talk it through. Everything that isn't thinking, we take off your hands."),
             art: "onboarding_hand_ipad"),
    ]

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                PaperBackground()
                decoration(in: geo.size)
                let layout = wide ? AnyLayout(HStackLayout(spacing: 48)) : AnyLayout(VStackLayout(spacing: 32))
                layout {
                    copy
                        .frame(maxWidth: 520, alignment: .leading)
                    Illustration(name: pages[page].art, maxHeight: wide ? geo.size.height * 0.62 : geo.size.height * 0.4)
                        .id(page)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, wide ? 72 : 48)
                .padding(.vertical, 40)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { go(page + 1) }
                if value.translation.width > 60 { go(page - 1) }
            })
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(pages[page].title)
                .font(TypeScale.display(56))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(pages[page].body)
                .font(TypeScale.hand(20, weight: 430))
                .foregroundStyle(Palette.ink2)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                LinkedDots(count: pages.count, current: page) { go($0) }
                Spacer(minLength: 0)
                if page < pages.count - 1 {
                    Button(String(localized: "Skip"), action: onFinish)
                        .foregroundStyle(Palette.ink2)
                    PrimaryButton(title: String(localized: "Next"), systemImage: "arrow.right") { go(page + 1) }
                } else {
                    PrimaryButton(title: String(localized: "Start mapping"), systemImage: "arrow.right", action: onFinish)
                }
            }
            .padding(.top, 12)
        }
        .id("copy-\(page)")
        .transition(RiseIn())
    }

    private func decoration(in size: CGSize) -> some View {
        ZStack {
            GrainBlob(color: Palette.butter, seed: 2)
                .frame(width: 420, height: 360)
                .position(x: size.width * 0.82, y: size.height * 0.18)
            GrainBlob(color: Palette.olive.opacity(0.35), seed: 5)
                .frame(width: 260, height: 220)
                .position(x: size.width * 0.1, y: size.height * 0.9)
        }
        .allowsHitTesting(false)
    }

    private func go(_ target: Int) {
        guard pages.indices.contains(target) else { return }
        withAnimation(.stopMotion(duration: 0.4, fps: 12)) { page = target }
    }
}

/// Page indicator in the collage style: circles joined by a line, current one filled.
struct LinkedDots: View {
    var count: Int
    var current: Int
    var onSelect: (Int) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                if i > 0 {
                    Rectangle().fill(Palette.ink).frame(width: 18, height: 1.5)
                }
                Button { onSelect(i) } label: {
                    Circle()
                        .strokeBorder(Palette.ink, lineWidth: 1.5)
                        .background(Circle().fill(i == current ? Palette.ink : .clear).padding(3))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Page \(i + 1)"))
            }
        }
        .animation(Motion.snappy, value: current)
        .boil(0.5, fps: 6)
    }
}
