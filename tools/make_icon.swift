// Exports the generated Vox paper artwork as an opaque 1024×1024 iOS app icon.
// Run from the repository root:
// swift tools/make_icon.swift [output.png] [source.png]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = Array(CommandLine.arguments.dropFirst())
let output = URL(fileURLWithPath: arguments.first
    ?? "ReMap/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let input = URL(fileURLWithPath: arguments.count > 1 ? arguments[1]
    : "art/branding/remap-connected-ideas.png")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("App icon: \(message)\n".utf8))
    exit(1)
}

guard input.standardizedFileURL != output.standardizedFileURL else {
    fail("source and output must be different files")
}
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("cannot read \(input.path)")
}
guard artwork.width == artwork.height else {
    fail("source artwork must be square; refusing to distort or crop it")
}

let size = 1024
guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fail("cannot create export context") }

let bounds = CGRect(x: 0, y: 0, width: size, height: size)
context.setFillColor(CGColor(srgbRed: 236.0 / 255, green: 232.0 / 255,
                             blue: 223.0 / 255, alpha: 1))
context.fill(bounds)
context.interpolationQuality = .high
context.draw(artwork, in: bounds)

do {
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
} catch { fail("cannot create output directory: \(error.localizedDescription)") }

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        output as CFURL, UTType.png.identifier as CFString, 1, nil
      ) else { fail("cannot create PNG export") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("PNG export failed") }
print("wrote \(output.path) (1024×1024, opaque sRGB)")
