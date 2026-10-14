// Renders Focal's 1024px app icon: a graphite tile with the timer's tick ruler and a
// glass lens magnifying it around the red marker.
// Usage: swift make_icon.swift <output.png>
import AppKit

let side: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(side), height: Int(side), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func white(_ alpha: CGFloat) -> CGColor { CGColor(gray: 1, alpha: alpha) }

/// Rounded rect with superellipse corners — close to Apple's continuous-corner icon shape.
func squircle(_ r: CGRect, radius: CGFloat, exponent n: CGFloat = 4.6) -> CGPath {
    let path = CGMutablePath()
    let steps = 48
    let corners: [(CGFloat, CGFloat, CGFloat)] = [
        (r.maxX - radius, r.maxY - radius, 0),
        (r.minX + radius, r.maxY - radius, .pi / 2),
        (r.minX + radius, r.minY + radius, .pi),
        (r.maxX - radius, r.minY + radius, 3 * .pi / 2),
    ]
    for (cx, cy, start) in corners {
        for i in 0...steps {
            let t = start + CGFloat(i) / CGFloat(steps) * .pi / 2
            let c = cos(t), s = sin(t)
            let point = CGPoint(x: cx + radius * copysign(pow(abs(c), 2 / n), c),
                                y: cy + radius * copysign(pow(abs(s), 2 / n), s))
            path.isEmpty ? path.move(to: point) : path.addLine(to: point)
        }
    }
    path.closeSubpath()
    return path
}

func linearGradient(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radialGradient(_ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                           options: [])
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = squircle(body, radius: 250)
let red = rgb(0xFF5340)

// Drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: CGColor(gray: 0, alpha: 0.38))
ctx.addPath(bodyPath)
ctx.setFillColor(rgb(0x18181B))
ctx.fillPath()
ctx.restoreGState()

// Tile: graphite gradient with a soft glow from the top.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
linearGradient([rgb(0x34343A), rgb(0x0C0C0E)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
radialGradient([white(0.09), white(0)], center: CGPoint(x: 380, y: 900), radius: 620)

// The tick ruler.
let bandMid: CGFloat = 512
let bandHalf: CGFloat = 118
let lens = CGPoint(x: 424, y: bandMid)  // midway between two ticks
let lensRadius: CGFloat = 172
let tickXs = stride(from: CGFloat(196), through: 830, by: 24).map { $0 }

func drawTicks(scale: CGFloat, about center: CGPoint) {
    for (index, x) in tickXs.enumerated() {
        let lit = x < lens.x - 4
        let quarter = index % 4 == 0
        let color = lit ? red : white(quarter ? 0.42 : 0.26)
        let width = 7 * scale
        let height = bandHalf * 2 * scale
        let cx = center.x + (x - center.x) * scale
        let rect = CGRect(x: cx - width / 2, y: center.y - height / 2, width: width, height: height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
        ctx.setFillColor(color)
        ctx.fillPath()
    }
}
drawTicks(scale: 1, about: lens)

// Lens shadow and body.
let lensRect = CGRect(x: lens.x - lensRadius, y: lens.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: CGColor(gray: 0, alpha: 0.55))
ctx.setFillColor(rgb(0x1A1A1E))
ctx.fillEllipse(in: lensRect)
ctx.restoreGState()

// Inside the lens: the ruler magnified, with the red marker.
ctx.saveGState()
ctx.addEllipse(in: lensRect)
ctx.clip()
linearGradient([rgb(0x2E2E34), rgb(0x141417)], from: CGPoint(x: lens.x, y: lensRect.maxY), to: CGPoint(x: lens.x, y: lensRect.minY))
drawTicks(scale: 1.8, about: lens)

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: rgb(0xFF3B2A, 0.9))
let marker = CGRect(x: lens.x - 7, y: lens.y - 132, width: 14, height: 264)
ctx.addPath(CGPath(roundedRect: marker, cornerWidth: 7, cornerHeight: 7, transform: nil))
ctx.setFillColor(rgb(0xFF4A38))
ctx.fillPath()
ctx.restoreGState()
// Hot core so the marker reads as the indicator, not another tick.
let core = CGRect(x: lens.x - 2, y: lens.y - 118, width: 4, height: 236)
ctx.addPath(CGPath(roundedRect: core, cornerWidth: 2, cornerHeight: 2, transform: nil))
ctx.setFillColor(rgb(0xFFD2C8, 0.9))
ctx.fillPath()

// Glass: a sheen from the top-left and a faint bounce light at the bottom.
radialGradient([white(0.26), white(0.06), white(0)], center: CGPoint(x: lens.x - 70, y: lens.y + 110), radius: 260)
radialGradient([white(0.08), white(0)], center: CGPoint(x: lens.x + 60, y: lens.y - 150), radius: 150)
ctx.restoreGState()

// Lens rim: bright edge, inner shade and a specular arc on the upper left.
ctx.setLineWidth(4)
ctx.setStrokeColor(white(0.4))
ctx.strokeEllipse(in: lensRect.insetBy(dx: 2, dy: 2))
ctx.setLineWidth(3)
ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.35))
ctx.strokeEllipse(in: lensRect.insetBy(dx: 6, dy: 6))
ctx.setLineCap(.round)
ctx.setLineWidth(9)
ctx.setStrokeColor(white(0.65))
ctx.addArc(center: lens, radius: lensRadius - 20, startAngle: .pi * 0.62, endAngle: .pi * 0.92, clockwise: false)
ctx.strokePath()
ctx.setLineWidth(5)
ctx.setStrokeColor(white(0.22))
ctx.addArc(center: lens, radius: lensRadius - 20, startAngle: .pi * 1.62, endAngle: .pi * 1.8, clockwise: false)
ctx.strokePath()

ctx.restoreGState()

// Thin light edge around the tile.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.addPath(bodyPath)
ctx.setLineWidth(5)
ctx.setStrokeColor(white(0.13))
ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
