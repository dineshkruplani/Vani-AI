import AppKit
import SwiftUI

/// A floating, borderless "Liquid Glass"-style overlay shown while dictating /
/// processing. Uses `NSVisualEffectView` (vibrancy) — the available approximation
/// of Liquid Glass on macOS 13–15.
@MainActor
final class HUDController {
    static let shared = HUDController()

    private var panel: NSPanel?
    private let model = HUDModel()
    private var hideWorkItem: DispatchWorkItem?

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: HUDView(model: model))
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(host)

        self.panel = panel
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 120
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Show the HUD with the given state. `autoHide` dismisses it after a delay.
    func show(icon: String, text: String, tint: Color = .primary, autoHide: TimeInterval? = nil) {
        ensurePanel()
        model.icon = icon
        model.text = text
        model.tint = tint
        position()
        panel?.orderFrontRegardless()

        hideWorkItem?.cancel()
        if let autoHide {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + autoHide, execute: work)
        }
    }

    func hide() {
        hideWorkItem?.cancel()
        panel?.orderOut(nil)
    }
}

/// Observable state for the HUD contents.
@MainActor
final class HUDModel: ObservableObject {
    @Published var icon: String = "mic.fill"
    @Published var text: String = ""
    @Published var tint: Color = .primary
}

/// The glassy pill rendered inside the floating panel.
private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(model.tint)
                .symbolRenderingMode(.hierarchical)
            Text(model.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .padding(6)
    }
}

/// Bridges `NSVisualEffectView` (the vibrancy / glass material) into SwiftUI.
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Lightweight system-sound cues.
@MainActor
enum SoundCue {
    static func start() { NSSound(named: "Tink")?.play() }
    static func done()  { NSSound(named: "Pop")?.play() }
    static func error() { NSSound(named: "Basso")?.play() }
}
