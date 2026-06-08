import SwiftUI

/// Soft drifting "aurora" background — 4 large blurred color blobs over a base tint.
/// Light/dark palettes per the Vani design system. Respects reduced-motion.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private var blobs: [Color] {
        scheme == .dark
            ? [Color(nsColor: NSColor(hex: 0x5A4BD8)), Color(nsColor: NSColor(hex: 0x7C3FA6)),
               Color(nsColor: NSColor(hex: 0x2E6FD8)), Color(nsColor: NSColor(hex: 0xB8487E))]
            : [Color(nsColor: NSColor(hex: 0xC8C1F8)), Color(nsColor: NSColor(hex: 0xC6E1F5)),
               Color(nsColor: NSColor(hex: 0xF7D6DE)), Color(nsColor: NSColor(hex: 0xCFEBDD))]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                VaniToken.bg
                blob(blobs[0], size: w * 0.9).position(x: w * (animate ? 0.28 : 0.22), y: h * 0.26)
                blob(blobs[1], size: w * 0.8).position(x: w * (animate ? 0.78 : 0.84), y: h * (animate ? 0.22 : 0.30))
                blob(blobs[2], size: w * 0.85).position(x: w * 0.30, y: h * (animate ? 0.82 : 0.74))
                blob(blobs[3], size: w * 0.75).position(x: w * (animate ? 0.74 : 0.68), y: h * 0.80)
            }
            .blur(radius: 36)
            .opacity(scheme == .dark ? 0.55 : 0.85)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 22).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }

    private func blob(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
    }
}
