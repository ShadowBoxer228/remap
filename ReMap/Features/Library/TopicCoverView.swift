import SwiftUI

struct TopicCoverView: View {
    var image: UIImage?
    var seed: Double
    var width: CGFloat
    var isWorking = false
    var symbol = "book.closed"

    var body: some View {
        Color.clear
            .frame(width: width, height: width * 0.75)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if isWorking {
                    Text("Illustrating…")
                        .font(TypeScale.hand(12))
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Palette.surface)
                        .padding(12)
                }
            }
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        GeometryReader { geo in
            ZStack {
                Palette.butter.opacity(0.48)
                Image("texture_paper").resizable(resizingMode: .tile)
                    .blendMode(.multiply).opacity(0.20)
                BlobShape(seed: seed, time: 0, wobble: 0.1)
                    .fill(Palette.olive.opacity(0.62))
                    .frame(width: geo.size.width * 0.66, height: geo.size.height * 0.72)
                    .rotationEffect(.degrees(-16))
                    .offset(x: 20, y: -2)
                LibraryPaperShape(seed: seed + 4)
                    .fill(Palette.surface)
                    .frame(width: geo.size.width * 0.43, height: geo.size.height * 0.61)
                    .rotationEffect(.degrees(-11))
                    .offset(x: -18, y: 8)
                Image(systemName: symbol)
                    .font(.system(size: geo.size.height * 0.25, weight: .ultraLight))
                    .foregroundStyle(Palette.ink)
                    .rotationEffect(.degrees(-11))
                    .offset(x: -18, y: 8)
                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Palette.ink2)
                    .offset(x: geo.size.width * 0.28, y: -geo.size.height * 0.25)
                Path { path in
                    path.move(to: CGPoint(x: geo.size.width * 0.15, y: geo.size.height * 0.76))
                    path.addQuadCurve(to: CGPoint(x: geo.size.width * 0.78, y: geo.size.height * 0.70),
                                      control: CGPoint(x: geo.size.width * 0.57, y: geo.size.height * 1.02))
                }
                .stroke(Palette.ink2, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
