import AppKit
import SwiftUI

/// The answer to a no-selection voice command, shown in the top-center HUD (same
/// place as the main dictation flow). Auto-dismisses after a few seconds, but stays
/// as long as the mouse hovers it.
@MainActor
final class AnswerHUDController {
    static let shared = AnswerHUDController()

    private var panel: NSPanel?
    private var hostView: NSHostingView<AnswerView>?
    private let model = AnswerModel()
    private var dismissWork: DispatchWorkItem?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(_ text: String) {
        ensurePanel()
        model.text = text
        model.onHoverChanged = { [weak self] hovering in
            if hovering { self?.cancelDismiss() } else { self?.scheduleDismiss(after: 1.5) }
        }
        resizeToFit()
        panel?.orderFrontRegardless()
        scheduleDismiss(after: 6.0)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 160),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false // needs hover detection
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: AnswerView(model: model))
        host.frame = panel.contentView!.bounds
        panel.contentView?.addSubview(host)
        self.panel = panel
        self.hostView = host
    }

    /// Grow the card to fit the reply (capped by the view's maxHeight), pinned top-center.
    private func resizeToFit() {
        guard let panel, let host = hostView else { return }
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        size.width = ceil(size.width); size.height = ceil(size.height)
        guard size.width > 1, size.height > 1 else { positionTopCenter(); return }
        panel.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        positionTopCenter()
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let host = self.hostView else { return }
            host.layoutSubtreeIfNeeded()
            var s = host.fittingSize
            s.width = ceil(s.width); s.height = ceil(s.height)
            guard s.width > 1, s.height > 1, s != panel.frame.size else { return }
            panel.setContentSize(s)
            host.frame = NSRect(origin: .zero, size: s)
            self.positionTopCenter()
        }
    }

    private func positionTopCenter() {
        guard let panel, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.maxY - size.height - 6
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

    // Fixed content width; the card grows in height to fit the reply (up to ~18 lines,
    // then truncates). Sized by fittingSize in the controller.
    private let contentWidth: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VaniToken.accent)
                Text("ANSWER")
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(model.text)
                .font(.system(size: 13.5))
                .lineSpacing(2)
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .lineLimit(18)
                .frame(width: contentWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(islandBackground)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 9, y: 5)
        .padding(28)
        .fixedSize()
        .onHover { hovering in model.onHoverChanged?(hovering) }
    }

    private var islandBackground: some View {
        ZStack {
            AnswerVisualEffect()
            LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x262634, alpha: 0.82)),
                                    Color(nsColor: NSColor(hex: 0x0C0D12, alpha: 0.90))],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
