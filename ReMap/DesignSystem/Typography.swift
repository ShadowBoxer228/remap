import SwiftUI
import UIKit
import CoreText

/// Variable-font axes we drive directly through CoreText (`Font.custom` can't set them).
enum FontAxis: String {
    case weight = "wght", informality = "INFM", bounce = "BNCE", spacing = "SPAC"

    var tag: UInt32 { rawValue.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
}

/// Builds `Font`s from bundled variable fonts with explicit axis values.
enum VariableFont {
    private static var cache: [String: UIFont] = [:]

    static func uiFont(_ postScriptName: String, size: CGFloat, axes: [FontAxis: CGFloat]) -> UIFont {
        let key = "\(postScriptName)|\(size)|" + axes.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ",")
        if let cached = cache[key] { return cached }
        guard let base = UIFont(name: postScriptName, size: size) else {
            return .systemFont(ofSize: size)
        }
        var variations: [NSNumber: CGFloat] = [:]
        for (axis, value) in axes { variations[NSNumber(value: axis.tag)] = value }
        let attribute = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let descriptor = base.fontDescriptor.addingAttributes([attribute: variations])
        let font = UIFont(descriptor: descriptor, size: size)
        cache[key] = font
        return font
    }

    /// Scales `size` with Dynamic Type relative to `style`, then builds the font.
    static func font(_ postScriptName: String, size: CGFloat, relativeTo style: UIFont.TextStyle? = nil,
                     axes: [FontAxis: CGFloat]) -> Font {
        let scaled = style.map { UIFontMetrics(forTextStyle: $0).scaledValue(for: size) } ?? size
        return Font(uiFont(postScriptName, size: scaled, axes: axes))
    }
}

/// Type scale for the collage look: a tight grotesk (SF Pro) for headlines and UI, and
/// Shantell Sans as the hand — the coach's notes, annotations and map nodes.
enum TypeScale {
    private static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: size)
    }

    static func display(_ size: CGFloat = 48) -> Font {
        .system(size: scaled(size, .largeTitle), weight: .bold).width(.condensed)
    }

    static func title(_ size: CGFloat = 30) -> Font {
        .system(size: scaled(size, .title1), weight: .semibold)
    }

    static func heading(_ size: CGFloat = 20) -> Font {
        .system(size: scaled(size, .title3), weight: .semibold)
    }

    /// Small caps-like overline labels ("STEP 2 · SORT").
    static func overline(_ size: CGFloat = 12) -> Font {
        .system(size: scaled(size, .caption1), weight: .bold).width(.expanded)
    }

    /// The coach writes by hand — like a tutor's pencil notes in the margin.
    static func coach(_ size: CGFloat = 21) -> Font {
        VariableFont.font("ShantellSans-Light", size: size, relativeTo: .title3,
                          axes: [.weight: 470, .informality: 75, .bounce: 0])
    }

    /// Node labels have a fixed size: the canvas zoom scales them, not Dynamic Type.
    static func node(backbone: Bool, size: CGFloat? = nil) -> Font {
        VariableFont.font("ShantellSans-Light", size: size ?? (backbone ? 22 : 18),
                          axes: [.weight: backbone ? 700 : 530, .informality: 45, .bounce: 0])
    }

    static func hand(_ size: CGFloat = 17, weight: CGFloat = 500) -> Font {
        VariableFont.font("ShantellSans-Light", size: size, relativeTo: .body,
                          axes: [.weight: weight, .informality: 70, .bounce: 0])
    }
}
