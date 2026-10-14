// Renders the DMG window background (660×400 pt) at 1x and 2x.
// Usage: swift make_dmg_background.swift <out-1x.png> <out-2x.png>
import AppKit

let size = CGSize(width: 660, height: 400)

func render(scale: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Light, so Finder's (always dark) icon labels stay readable; the dark app icon pops on it.
    NSGradient(starting: NSColor(srgbRed: 0.975, green: 0.975, blue: 0.98, alpha: 1),
               ending: NSColor(srgbRed: 0.9, green: 0.9, blue: 0.915, alpha: 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // A faint tick ruler along the bottom edge, red up to a third of the way.
    for (index, x) in stride(from: CGFloat(30), through: size.width - 30, by: 9).enumerated() {
        let lit = x < size.width * 0.34
        (lit ? NSColor(srgbRed: 0.96, green: 0.3, blue: 0.22, alpha: 0.7)
             : NSColor(white: 0, alpha: index % 4 == 0 ? 0.16 : 0.08)).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 14, width: 2, height: 16), xRadius: 1, yRadius: 1).fill()
    }

    func text(_ string: String, size fontSize: CGFloat, weight: NSFont.Weight, alpha: CGFloat, centerY: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor(white: 0, alpha: alpha),
            .paragraphStyle: paragraph,
        ])
        let height = attributed.size().height
        // Finder coordinates run top-down; convert to bottom-up.
        attributed.draw(in: NSRect(x: 0, y: size.height - centerY - height / 2, width: size.width, height: height))
    }

    text("Focal", size: 30, weight: .semibold, alpha: 0.88, centerY: 50)
    text("a liquid-glass focus timer for your menu bar", size: 13, weight: .regular, alpha: 0.5, centerY: 82)

    // Arrow from the app to Applications (icons sit at y = 200, x = 170 and 490).
    let arrowY = size.height - 196
    NSColor(white: 0, alpha: 0.28).setStroke()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 262, y: arrowY))
    shaft.line(to: NSPoint(x: 394, y: arrowY))
    shaft.lineWidth = 2.5
    shaft.lineCapStyle = .round
    shaft.setLineDash([2, 7], count: 2, phase: 0)
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 386, y: arrowY + 9))
    head.line(to: NSPoint(x: 398, y: arrowY))
    head.line(to: NSPoint(x: 386, y: arrowY - 9))
    head.lineWidth = 2.5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    text("drag Focal into Applications to install", size: 13, weight: .medium, alpha: 0.7, centerY: 298)
    text("first launch blocked? System Settings → Privacy & Security → Open Anyway",
         size: 10.5, weight: .regular, alpha: 0.42, centerY: 322)
    text("made by Dhruv", size: 12, weight: .semibold, alpha: 0.6, centerY: 346)

    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

render(scale: 1, to: CommandLine.arguments[1])
render(scale: 2, to: CommandLine.arguments[2])
