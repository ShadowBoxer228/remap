// Prepares generated collage art for the app: hardens cut-out edges (removes soft glow halos and
// colored fringes from the image model), downsizes, and writes asset-catalog image sets.
// Usage: swift tools/prepare_art.swift art/generated ReMap/Resources/Assets.xcassets/Illustrations
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args.count > 1 ? args[1] : "art/generated")
let output = URL(fileURLWithPath: args.count > 2 ? args[2] : "ReMap/Resources/Assets.xcassets/Illustrations")
let maxSide = 1400

/// Alpha remap per asset: (low, high) — alpha below `low` vanishes, above `high` is solid.
let edgeCurves: [String: (Double, Double)] = [
    "onboarding_hand_ipad": (0.55, 0.75),
    "library_empty": (0.55, 0.75),
]
let defaultCurve = (0.18, 0.45)

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let folderInfo = #"{ "info" : { "author" : "xcode", "version" : 1 }, "properties" : { "provides-namespace" : false } }"#
try folderInfo.write(to: output.appending(path: "Contents.json"), atomically: true, encoding: .utf8)

let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "png" }
for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let name = file.deletingPathExtension().lastPathComponent
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("skip \(name)"); continue }
    let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
    let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
    let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    if hasAlpha, let data = ctx.data {
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let (lo, hi) = edgeCurves[name] ?? defaultCurve
        for i in 0..<(w * h) {
            let o = i * 4
            let a = Double(px[o + 3]) / 255
            guard a > 0 else { continue }
            let newA = smoothstep(lo, hi, a)
            // Un-premultiply with the old alpha, re-premultiply with the new one.
            for c in 0..<3 {
                let straight = min(Double(px[o + c]) / a, 255)
                px[o + c] = UInt8(min(255, max(0, straight * newA)))
            }
            px[o + 3] = UInt8(newA * 255)
        }
    }
    let set = output.appending(path: "\(name).imageset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    let out = set.appending(path: "\(name).png")
    let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    let contents = """
    { "images" : [ { "filename" : "\(name).png", "idiom" : "universal" } ], "info" : { "author" : "xcode", "version" : 1 } }
    """
    try contents.write(to: set.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    let bytes = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
    print("\(name): \(w)x\(h) alpha=\(hasAlpha) \(bytes / 1024)KB")
}
