import SwiftUI
import AppKit

/// `NSVisualEffectView` bridge — the Liquid-Glass material (vibrancy/backdrop blur).
struct VaniVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

/// A frosted glass panel background: material + hairline border + bright inset top edge + soft shadow.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = VaniRadius.card
    var material: NSVisualEffectView.Material = .hudWindow
    var shadow: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                VaniVisualEffect(material: material)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(VaniToken.glassEdge, lineWidth: 1)
                    .blendMode(.plusLighter)
                    .opacity(0.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(VaniToken.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(shadow ? 0.22 : 0),
                    radius: shadow ? 24 : 0, x: 0, y: shadow ? 12 : 0)
    }
}

extension View {
    /// Apply the Vani liquid-glass panel style.
    func glassPanel(cornerRadius: CGFloat = VaniRadius.card,
                    material: NSVisualEffectView.Material = .hudWindow,
                    shadow: Bool = true) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, material: material, shadow: shadow))
    }
}
