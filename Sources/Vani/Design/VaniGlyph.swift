import AppKit

/// Renders the Vani logo mark (single-stroke "va" + voice dot) as an NSImage —
/// used for the menu-bar icon. `template` lets the menu bar tint it for light/dark.
enum VaniGlyph {
    static func image(size: CGFloat = 18, color: NSColor, template: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let s = size / 100
            // SVG coords are top-down; AppKit is bottom-up — flip y.
            func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: size - y * s) }

            let path = NSBezierPath()
            path.move(to: P(40, 24))
            path.curve(to: P(67, 42), controlPoint1: P(40, 60), controlPoint2: P(72, 62))
            path.curve(to: P(46, 51), controlPoint1: P(63, 27), controlPoint2: P(45, 30))
            path.curve(to: P(62, 73), controlPoint1: P(47, 65), controlPoint2: P(55, 71))
            path.lineWidth = 8 * s
            path.lineCapStyle = .round
            color.setStroke()
            path.stroke()

            let dr = 8.5 * s
            let c = P(33, 60)
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - dr, y: c.y - dr, width: dr * 2, height: dr * 2)).fill()
            return true
        }
        img.isTemplate = template
        return img
    }
}
