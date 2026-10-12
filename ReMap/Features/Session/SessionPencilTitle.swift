import SwiftUI

/// The session's handwritten label. The paper and graphite stay still while working.
struct SessionPencilTitle: View {
    var title: String
    var onRename: (String) -> Void

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isFocused: Bool
    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 3) {
            if isEditing {
                TextField(String(localized: "Title"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(TypeScale.hand(21, weight: 470))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .focused($isFocused)
                    .onAppear { isFocused = true }
                    .submitLabel(.done)
                    .onSubmit(commitRename)
                    .onKeyPress(.escape) {
                        cancelRename()
                        return .handled
                    }
                    .accessibilityLabel(Text("Title"))
            } else {
                lettering
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginRename)
                    .accessibilityAddTraits([.isHeader, .isButton])
                    .accessibilityHint(Text("Double-tap to rename"))
                    .accessibilityAction(.default, beginRename)
                    .accessibilityAction(named: Text("Rename"), beginRename)
                    .contextMenu {
                        Button(String(localized: "Rename"), systemImage: "pencil", action: beginRename)
                    }
            }

            PencilTitleUnderline()
                .stroke(Palette.ink2.opacity(isEditing || contrast == .increased ? 0.85 : 0.48),
                        style: StrokeStyle(lineWidth: isEditing ? 1.2 : 0.8, lineCap: .round))
                .frame(height: 4)
                .padding(.horizontal, 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 17)
        .padding(.top, 9)
        .padding(.bottom, 7)
        .frame(minHeight: 50)
        .frame(maxWidth: .infinity)
        .background {
            PencilTitlePaper()
                .fill(Palette.surface)
                .overlay {
                    Image("texture_paper")
                        .resizable(resizingMode: .tile)
                        .blendMode(.multiply)
                        .opacity(0.13)
                        .clipShape(PencilTitlePaper())
                }
                .overlay {
                    PencilTitlePaper()
                        .stroke(Palette.ink2.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: 0.65)
                }
                .shadow(color: .black.opacity(0.07), radius: 0.7, x: 0, y: 1.2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused && !focused { commitRename() }
        }
    }

    private var lettering: some View {
        Text(verbatim: title)
            .font(TypeScale.hand(21, weight: 470))
            .foregroundStyle(Palette.ink.opacity(contrast == .increased ? 1 : 0.9))
            .multilineTextAlignment(.center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .overlay {
                if contrast != .increased {
                    PencilTitleGraphite()
                        .blendMode(.destinationOut)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .compositingGroup()
    }

    private func beginRename() {
        draft = title
        isEditing = true
    }

    private func commitRename() {
        guard isEditing else { return }
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        isFocused = false
        if !value.isEmpty && value != title { onRename(value) }
    }

    private func cancelRename() {
        isEditing = false
        isFocused = false
    }
}

/// Tiny fixed flecks break up solid ink without a shader, animation or bitmap text.
private struct PencilTitleGraphite: View {
    var body: some View {
        Canvas { context, size in
            var flecks = Path()
            for row in 0..<Int(size.height / 1.9) {
                for column in 0..<Int(size.width / 2.1) {
                    let seed = (row * 73 + column * 37) % 101
                    let x = CGFloat(column) * 2.1 + CGFloat(seed % 7) * 0.18
                    let y = CGFloat(row) * 1.9 + CGFloat(seed % 11) * 0.11
                    flecks.addEllipse(in: CGRect(x: x, y: y,
                                                width: 0.45 + CGFloat(seed % 3) * 0.15, height: 0.4))
                }
            }
            context.fill(flecks, with: .color(.black.opacity(0.23)))
        }
    }
}

nonisolated private struct PencilTitlePaper: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 3, y: 2.2))
        path.addLine(to: CGPoint(x: w * 0.29, y: 0.9))
        path.addLine(to: CGPoint(x: w * 0.68, y: 1.7))
        path.addLine(to: CGPoint(x: w - 2.1, y: 0.8))
        path.addLine(to: CGPoint(x: w - 0.8, y: h * 0.43))
        path.addLine(to: CGPoint(x: w - 2.8, y: h - 1.7))
        path.addLine(to: CGPoint(x: w * 0.72, y: h - 0.6))
        path.addLine(to: CGPoint(x: w * 0.34, y: h - 1.6))
        path.addLine(to: CGPoint(x: 1.1, y: h - 0.7))
        path.addLine(to: CGPoint(x: 2.2, y: h * 0.57))
        path.closeSubpath()
        return path
    }
}

nonisolated private struct PencilTitleUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.06, y: 2))
        path.addCurve(to: CGPoint(x: rect.width * 0.94, y: 1.2),
                      control1: CGPoint(x: rect.width * 0.34, y: 0.2),
                      control2: CGPoint(x: rect.width * 0.63, y: 3.1))
        path.move(to: CGPoint(x: rect.width * 0.18, y: 3.1))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.8, y: 2.5),
                         control: CGPoint(x: rect.width * 0.52, y: 2.1))
        return path
    }
}
