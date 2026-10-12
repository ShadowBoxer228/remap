import SwiftUI

enum CoachControlTone { case quiet, paper, primary, end }

/// Shared coach controls: flat paper tabs with generous, nonoverlapping hit areas.
struct CoachControlStyle: ButtonStyle {
    var tone: CoachControlTone = .paper
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tone == .primary ? Palette.surface : tone == .end ? Palette.accent : Palette.ink)
            .padding(.horizontal, 10)
            .frame(minWidth: 44, minHeight: 44)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private var background: Color {
        switch tone {
        case .quiet: .clear
        case .paper: Palette.surfaceSunken.opacity(0.7)
        case .primary: Palette.ink
        case .end: Palette.accentSoft
        }
    }
}

struct CoachIconButton: View {
    var label: String
    var symbol: String
    var tone: CoachControlTone = .paper
    var action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(CoachControlStyle(tone: tone))
            .accessibilityLabel(label)
            .help(label)
    }
}

struct CoachPaperSurface: ViewModifier {
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.surface)
                    .grain(0.035)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.hairline.opacity(0.8), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }
}

struct CoachActionReceipt: View {
    var summary: String
    var canUndo: Bool
    var undo: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "checkmark").foregroundStyle(Palette.oliveDeep)
                .accessibilityHidden(true)
            Text(summary).font(.caption).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if canUndo {
                CoachIconButton(label: String(localized: "Undo coach change"), symbol: "arrow.uturn.backward", tone: .quiet, action: undo)
            }
        }
        .padding(.leading, 10)
        .background(Palette.butter.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
