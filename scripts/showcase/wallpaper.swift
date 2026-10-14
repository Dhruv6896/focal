// Renders the showcase wallpaper (1200×675 pt at 2x): near-black with a faint red ember.
// Usage: swift wallpaper.swift <out.png>
import AppKit

let size = CGSize(width: 1200, height: 675)
let scale: CGFloat = 2
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let base = CGGradient(colorsSpace: space, colors: [color(0x0E0E11), color(0x050506)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])

// Near-black with a low ember of Focal red and a little cool light, so the glass has
// something faint to catch without colouring the scene.
let glows: [(CGFloat, CGFloat, CGFloat, UInt32, CGFloat)] = [
    (0.84, 0.10, 0.55, 0xFF4A38, 0.30),
    (0.62, 0.72, 0.40, 0xFF6A4D, 0.10),
    (0.10, 0.92, 0.45, 0x9AA4B5, 0.10),
]
for (x, y, r, hex, strength) in glows {
    let center = CGPoint(x: x * size.width, y: y * size.height)
    let gradient = CGGradient(colorsSpace: space, colors: [color(hex, strength), color(hex, 0)] as CFArray,
                              locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                           endRadius: r * size.width, options: [])
}

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
