import AppKit
import CoreText

/// Draws the menu bar pill as a template image so it adapts to light/dark menu bars.
enum StatusItemRenderer {
    enum PillStyle { case filled, outlined }

    /// `symbol` (an SF Symbol name) is drawn before the text, e.g. a cup during breaks.
    static func pill(_ text: String, style: PillStyle, bold: Bool, alpha: CGFloat = 1, symbol: String? = nil) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: bold ? .bold : .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let textWidth = ceil(CTLineGetTypographicBounds(line, nil, nil, nil))

        let height: CGFloat = 17
        let horizontalPadding: CGFloat = 7
        let symbolImage = symbol.flatMap { name in
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: bold ? .bold : .semibold))
        }
        let symbolWidth = symbolImage.map { ceil($0.size.width) + 3 } ?? 0
        let size = NSSize(width: symbolWidth + textWidth + horizontalPadding * 2, height: height)
        let lineWidth: CGFloat = bold ? 1.6 : 1.2

        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)

            let inset = style == .outlined ? lineWidth / 2 : 0
            let pillRect = rect.insetBy(dx: inset, dy: inset)
            let radius: CGFloat = 5
            let path = CGPath(roundedRect: pillRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)

            switch style {
            case .filled:
                ctx.addPath(path)
                ctx.fillPath()
                // Knock the digits out of the pill.
                ctx.setBlendMode(.destinationOut)
            case .outlined:
                ctx.setLineWidth(lineWidth)
                ctx.addPath(path)
                ctx.strokePath()
            }

            if let symbolImage {
                let symbolRect = NSRect(
                    x: horizontalPadding, y: ((height - symbolImage.size.height) / 2).rounded(),
                    width: symbolImage.size.width, height: symbolImage.size.height
                )
                symbolImage.draw(in: symbolRect, from: .zero,
                                 operation: style == .filled ? .destinationOut : .sourceOver, fraction: 1)
            }

            ctx.textMatrix = .identity
            let baseline = ((height - font.capHeight) / 2).rounded()
            ctx.textPosition = CGPoint(x: horizontalPadding + symbolWidth, y: baseline)
            CTLineDraw(line, ctx)

            ctx.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Compact style: a ring that empties as time runs out, followed by a short label.
    static func ring(progress: Double, text: String, bold: Bool, alpha: CGFloat = 1) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: bold ? .bold : .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let textWidth = ceil(CTLineGetTypographicBounds(line, nil, nil, nil))

        let height: CGFloat = 17
        let diameter: CGFloat = 13
        let gap: CGFloat = 4
        let size = NSSize(width: diameter + gap + textWidth + 1, height: height)
        let fraction = CGFloat(min(max(progress, 0), 1))

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)

            let circle = CGRect(x: 0.5, y: (height - diameter) / 2, width: diameter, height: diameter)
            let center = CGPoint(x: circle.midX, y: circle.midY)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1.4)
            ctx.strokeEllipse(in: circle.insetBy(dx: 0.7, dy: 0.7))

            if fraction > 0 {
                // Pie of the time left, starting at 12 o'clock and running clockwise.
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.move(to: center)
                let start = CGFloat.pi / 2
                ctx.addArc(center: center, radius: diameter / 2 - 2.6, startAngle: start,
                           endAngle: start - fraction * 2 * .pi, clockwise: true)
                ctx.closePath()
                ctx.fillPath()
            }

            ctx.setFillColor(NSColor.black.cgColor)
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: diameter + gap, y: ((height - font.capHeight) / 2).rounded())
            CTLineDraw(line, ctx)

            ctx.endTransparencyLayer()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func symbol(_ name: String, alpha: CGFloat = 1) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "Focal")?
            .withSymbolConfiguration(config) else { return NSImage() }
        guard alpha < 1 else {
            base.isTemplate = true
            return base
        }
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            return true
        }
        image.isTemplate = true
        return image
    }
}
