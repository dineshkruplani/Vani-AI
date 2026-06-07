import AppKit
import SwiftUI

/// A floating answer popover shown near the mouse (used when the Command key is
/// pressed with nothing selected → the spoken question is answered here).
/// Auto-dismisses after a few seconds, but stays as long as the mouse hovers it.
@MainActor
final class AnswerHUDController {
    static let shared = AnswerHUDController()

    private var panel: NSPanel?
    private let model = AnswerModel()
    private var dismissWork: DispatchWorkItem?

    func show(_ text: String) {
        ensurePanel()
        model.text = text
        model.onHoverChanged = { [weak self] hovering in
            if hovering { self?.cancelDismiss() } else { self?.scheduleDismiss(after: 1.2) }
        }
        positionNearMouse()
        panel?.orderFrontRegardless()
        scheduleDismiss(after: 4.0)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
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
        panel.ignoresMouseEvents = false // needs hover detection
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: AnswerView(model: model))
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(host)
        self.panel = panel
    }

    private func positionNearMouse() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation // screen coords, origin bottom-left
        let size = panel.frame.size
        var x = mouse.x + 16
        var y = mouse.y - size.height - 16
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            x = min(max(vf.minX + 8, x), vf.maxX - size.width - 8)
            y = min(max(vf.minY + 8, y), vf.maxY - size.height - 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        cancelDismiss()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelDismiss() {
        dismissWork?.cancel()
        dismissWork = nil
    }
}

@MainActor
final class AnswerModel: ObservableObject {
    @Published var text: String = ""
    var onHoverChanged: ((Bool) -> Void)?
}

private struct AnswerView: View {
    @ObservedObject var model: AnswerModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            ScrollView {
                Text(model.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            AnswerVisualEffect().clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .padding(6)
        .onHover { hovering in model.onHoverChanged?(hovering) }
    }
}

private struct AnswerVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
