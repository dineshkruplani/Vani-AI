import SwiftUI
import AppKit

// MARK: - Color helpers

extension Color {
    /// A color that adapts to light/dark appearance automatically.
    init(lightHex: UInt32, lightAlpha: Double = 1, darkHex: UInt32, darkAlpha: Double = 1) {
        let ns = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(hex: darkHex, alpha: darkAlpha)
                          : NSColor(hex: lightHex, alpha: lightAlpha)
        }
        self.init(nsColor: ns)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Design tokens (Liquid Glass / "Iris" system)

/// Brand + UI tokens. Colors are appearance-adaptive (light/dark) per the Vani design system.
enum VaniToken {
    // Accent — "Iris"
    static let accent      = Color(lightHex: 0x6F6BE0, darkHex: 0x8E8BF2)
    static let accentDeep  = Color(lightHex: 0x524FCB, darkHex: 0xA8A5F7)
    static let accentSoft  = Color(lightHex: 0x6F6BE0, lightAlpha: 0.13, darkHex: 0x8E8BF2, darkAlpha: 0.18)
    static let accentText  = Color(lightHex: 0x524FCB, darkHex: 0xB6B3F9)

    // Text
    static let text   = Color(lightHex: 0x1F2027, darkHex: 0xF1F1EF)
    static let text2  = Color(lightHex: 0x5C5E69, darkHex: 0x9C9EA9)
    static let text3  = Color(lightHex: 0x9A9CA6, darkHex: 0x65676F)

    // Surfaces / glass
    static let bg        = Color(lightHex: 0xECEAE3, darkHex: 0x0B0C11)
    static let surface   = Color(lightHex: 0xFFFFFF, lightAlpha: 0.55, darkHex: 0xFFFFFF, darkAlpha: 0.07)
    static let surface2  = Color(lightHex: 0xFFFFFF, lightAlpha: 0.34, darkHex: 0xFFFFFF, darkAlpha: 0.04)
    static let border    = Color(lightHex: 0x22232B, lightAlpha: 0.10, darkHex: 0xFFFFFF, darkAlpha: 0.10)
    static let hairline  = Color(lightHex: 0x22232B, lightAlpha: 0.08, darkHex: 0xFFFFFF, darkAlpha: 0.07)
    static let glassEdge = Color(lightHex: 0xFFFFFF, lightAlpha: 0.60, darkHex: 0xFFFFFF, darkAlpha: 0.22)

    // Semantic
    static let good     = Color(lightHex: 0x2E9E6B, darkHex: 0x43B981)
    static let goodSoft = Color(lightHex: 0x2E9E6B, lightAlpha: 0.14, darkHex: 0x43B981, darkAlpha: 0.18)
    static let warn     = Color(lightHex: 0xC7892B, darkHex: 0xD9A441)
}

/// Corner radii from the design system.
enum VaniRadius {
    static let window: CGFloat = 15
    static let largeCard: CGFloat = 17
    static let card: CGFloat = 12
    static let button: CGFloat = 10
    static let field: CGFloat = 10
    static let island: CGFloat = 24
    static let pill: CGFloat = 9
}
