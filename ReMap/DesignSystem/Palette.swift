import SwiftUI
import UIKit

nonisolated extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

nonisolated extension Color {
    /// A color that resolves differently in light and dark appearance.
    /// `nonisolated`: SwiftUI resolves dynamic colors on its render thread, not the main actor.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

/// Design tokens — "Vox explainer collage": cream paper, olive grain, butter-yellow panels, olive-black ink.
enum Palette {
    static let canvas = Color(light: 0xECE8DF, dark: 0x191A16)
    static let dotGrid = Color(light: 0xD8D3C5, dark: 0x2D2F28)
    static let surface = Color(light: 0xF6F3EC, dark: 0x23241F)
    static let surfaceSunken = Color(light: 0xE3DED2, dark: 0x1D1E1A)
    static let hairline = Color(light: 0xD3CDBF, dark: 0x36382F)
    static let ink = Color(light: 0x2B2E26, dark: 0xECE8DF)
    static let ink2 = Color(light: 0x5D6052, dark: 0xAEB0A2)
    static let ink3 = Color(light: 0x8C8E80, dark: 0x75776B)
    /// Brand olive — the grainy "cloud" color.
    static let olive = Color(light: 0xA9A66B, dark: 0xB9B67C)
    static let oliveDeep = Color(light: 0x6F7040, dark: 0xC9C68C)
    /// Butter-yellow panels.
    static let butter = Color(light: 0xF3EDB0, dark: 0x4A4826)
    /// The coach's highlighter: what it wants you to look at.
    static let highlighter = Color(light: 0xF2E27A, dark: 0x8C7F22)
    /// Problems and warnings — used sparingly.
    static let accent = Color(light: 0xB5552E, dark: 0xE98A5E)
    static let accentSoft = Color(light: 0xF1DDD0, dark: 0x3D2519)
    static let success = Color(light: 0x5F7F3E, dark: 0xA6C97F)

    /// Muted categorical palette for groups; always paired with a glyph so color never carries meaning alone.
    static let branches: [Color] = [
        Color(light: 0x3F6E86, dark: 0x7FB2CC), // slate blue
        Color(light: 0xB5552E, dark: 0xE98A5E), // rust
        Color(light: 0x4E7D5B, dark: 0x8CC29A), // sage
        Color(light: 0xC08A1E, dark: 0xE9B95A), // ochre
        Color(light: 0x7B4F72, dark: 0xC597BC), // plum
        Color(light: 0x8A8640, dark: 0xC2BE72), // olive
    ]
    /// Paired glyphs so color never carries meaning alone.
    static let branchGlyphs = ["circle.fill", "triangle.fill", "square.fill", "diamond.fill", "hexagon.fill", "seal.fill"]

    static func branch(_ index: Int?) -> Color {
        guard let index else { return ink2 }
        return branches[((index % branches.count) + branches.count) % branches.count]
    }

    static func glyph(_ index: Int?) -> String? {
        guard let index else { return nil }
        return branchGlyphs[((index % branchGlyphs.count) + branchGlyphs.count) % branchGlyphs.count]
    }

    static func role(_ role: HeadlineRole) -> Color {
        switch role {
        case .backbone: oliveDeep
        case .topic: branches[0]
        case .detail: branches[2]
        }
    }
}
