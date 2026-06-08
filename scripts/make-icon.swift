// Renders the Vani app icon to an .iconset (run via: swift scripts/make-icon.swift <iconset-dir>)
// Iris gradient squircle + white single-stroke "va" glyph + voice dot. Headless CoreGraphics.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF)/255, green: CGFloat((hex >> 8) & 0xFF)/255,
            blue: CGFloat(hex & 0xFF)/255, alpha: 1)
}

func drawIcon(size: Int, to url: URL) {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    // Flip to top-left origin so SVG-style coords work directly.
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1)

    // Squircle background with the Iris gradient.
    let r = s * 0.224
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let bg = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [rgb(0x8E8BF2), rgb(0x524FCB)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])
    ctx.restoreGState()

    // Mark occupies ~62% centered. viewBox 0..100 → markScale.
    let markScale = s * 0.62 / 100
    let o = s * 0.19
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o + x*markScale, y: o + y*markScale) }

    let mark = CGMutablePath()
    mark.move(to: P(40, 24))
    mark.addCurve(to: P(67, 42), control1: P(40, 60), control2: P(72, 62))
    mark.addCurve(to: P(46, 51), control1: P(63, 27), control2: P(45, 30))
    mark.addCurve(to: P(62, 73), control1: P(47, 65), control2: P(55, 71))

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(8 * markScale)
    ctx.setLineCap(.round)
    ctx.addPath(mark); ctx.strokePath()

    // Voice dot.
    let dotR = 8.5 * markScale
    let c = P(33, 60)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: c.x - dotR, y: c.y - dotR, width: dotR*2, height: dotR*2))

    guard let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Vani.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (pixelSize, filename) per Apple's iconset spec.
let entries: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
for (px, name) in entries {
    drawIcon(size: px, to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("Wrote \(entries.count) icon sizes to \(outDir)")
