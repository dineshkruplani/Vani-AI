import SwiftUI
import AppKit
import CoreText

/// Bundled brand fonts (Hanken Grotesk / Newsreader / Spline Sans Mono), registered at launch.
/// Falls back gracefully to system fonts if the files aren't present (e.g. `swift run` without a bundle).
enum Fonts {
    /// Register any .ttf/.otf shipped in the app bundle's Resources.
    static func registerBundled() {
        for ext in ["ttf", "otf"] {
            for url in Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [] {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    private static func resolve(_ candidates: [String], _ size: CGFloat) -> String? {
        candidates.first { NSFont(name: $0, size: size) != nil }
    }

    /// Wordmark — Hanken Grotesk (falls back to rounded system).
    static func wordmark(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if let name = resolve(["Hanken Grotesk", "HankenGrotesk-SemiBold", "HankenGrotesk-Regular", "HankenGrotesk"], size) {
            return .custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    /// Mono labels / timers / keys — Spline Sans Mono (falls back to system mono).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let name = resolve(["Spline Sans Mono", "SplineSansMono-Regular", "SplineSansMono"], size) {
            return .custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    /// Poetic accent — Newsreader italic (falls back to system serif italic).
    static func serif(_ size: CGFloat) -> Font {
        if let name = resolve(["Newsreader", "Newsreader-Italic", "NewsreaderItalic"], size) {
            return .custom(name, size: size).italic()
        }
        return .system(size: size, design: .serif).italic()
    }
}
