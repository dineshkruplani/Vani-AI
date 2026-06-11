import AppKit
import SwiftUI

/// Lifecycle phases shown in the dynamic-island HUD.
enum HUDPhase: Equatable {
    case idle                       // "Hold ⌥ to talk" prompt in a text field
    case listening(command: Bool)   // command = orange/ask styling
    case transcribing
    case cleaning
    case inserted
    case error
}

/// A floating "dynamic island" — a dark-glass capsule near the bottom of the screen
/// that morphs through the dictation lifecycle.
@MainActor
final class HUDController {
    static let shared = HUDController()

    private var panel: NSPanel?
    private var hostView: NSHostingView<IslandView>?
    private let model = HUDModel()
    private var hideWorkItem: DispatchWorkItem?

    func show(phase: HUDPhase, title: String, detail: String = "", autoHide: TimeInterval? = nil) {
        guard SettingsStore.shared.showFloatingIndicator else { return }
        ensurePanel()
        if case .listening = phase, model.phase != phase { model.startedAt = Date() }
        model.phase = phase
        model.title = title
        model.detail = detail
        panel?.ignoresMouseEvents = true   // transient HUDs are click-through
        resizeToFit()
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

    /// Feed the live mic level (0…1) so the waveform reacts to the voice.
    func setLevel(_ level: CGFloat) {
        model.level = max(0, min(1, level))
    }

    /// Show/hide the idle "Hold … to talk" prompt (driven by FocusWatcher). Never
    /// clobbers an active (non-idle) HUD that's currently on screen.
    func setIdlePrompt(_ shouldShow: Bool) {
        guard SettingsStore.shared.showFloatingIndicator else { return }
        let visible = panel?.isVisible ?? false
        if shouldShow {
            if visible && model.phase != .idle { return }   // a real HUD is up — leave it
            ensurePanel()
            hideWorkItem?.cancel()
            model.phase = .idle
            model.title = ""
            model.detail = ""
            panel?.ignoresMouseEvents = false   // idle prompt needs hover (to dim)
            resizeToFit()
            panel?.orderFrontRegardless()
        } else if visible && model.phase == .idle {
            hide()
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No OS window shadow — it caches the previous (wider) capsule outline and leaves
        // a ghost border when the content shrinks. The capsule's own SwiftUI shadow
        // redraws with each state instead.
        panel.hasShadow = false
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: IslandView(model: model))
        host.frame = panel.contentView!.bounds
        panel.contentView?.addSubview(host)
        self.panel = panel
        self.hostView = host
    }

    /// Size the panel to exactly fit the island (capsule + shadow margin), then pin it
    /// top-center. Synchronous via SwiftUI's fittingSize — reliable across state changes.
    private func resizeToFit() {
        guard let panel, let host = hostView else { return }
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        size.width = ceil(size.width)
        size.height = ceil(size.height)
        guard size.width > 1, size.height > 1 else { position(); return }
        panel.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        position()
        // Second pass next runloop — covers cases where the SwiftUI state hadn't fully
        // propagated on the first measure (e.g. first show of a wider state).
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let host = self.hostView else { return }
            host.layoutSubtreeIfNeeded()
            var s = host.fittingSize
            s.width = ceil(s.width); s.height = ceil(s.height)
            guard s.width > 1, s.height > 1, s != panel.frame.size else { return }
            panel.setContentSize(s)
            host.frame = NSRect(origin: .zero, size: s)
            self.position()
        }
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        // Top-center, 6px under the menu bar — iPhone Dynamic Island placement.
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var phase: HUDPhase = .transcribing
    @Published var title: String = ""
    @Published var detail: String = ""
    @Published var level: CGFloat = 0   // live mic level 0…1 (drives the waveform)
    var startedAt = Date()
}

// MARK: - Island view

private struct IslandView: View {
    @ObservedObject var model: HUDModel
    @State private var idleHovered = false

    private var isListening: Bool {
        if case .listening = model.phase { return true }
        return false
    }

    private var dimmed: Bool { model.phase == .idle && idleHovered }

    var body: some View {
        content
            .padding(.horizontal, 18)
            .frame(height: 52)
            .frame(minWidth: 160)
            .background(islandBackground)
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 9, y: 5)
            .opacity(dimmed ? 0.2 : 1)          // hover the idle prompt → peek behind it
            .onHover { hovering in
                guard model.phase == .idle else { return }
                withAnimation(.easeOut(duration: 0.15)) { idleHovered = hovering }
            }
            .padding(.top, 22)                   // keep the island near the menu bar…
            .padding(.bottom, 34)                // …with extra room below for the shadow
            .padding(.horizontal, 28)
            .fixedSize()
    }

    @ViewBuilder private var content: some View {
        if model.phase == .idle {
            idleContent
        } else {
            standardContent
        }
    }

    // "● Hold [Right Option] to talk" — shown when the user focuses a text field anywhere.
    private var idleContent: some View {
        HStack(spacing: 9) {
            Circle().fill(VaniToken.accent).frame(width: 9, height: 9)
            Text("Hold").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            KeyCap(glyph: SettingsStore.shared.dictationHotkey.glyph)
            Text("to talk").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        }
    }

    private var standardContent: some View {
        HStack(spacing: 11) {
            leading
            if isListening { Waveform(level: model.level) }
            // Title + inline muted detail, e.g. "Cleaning up · gpt-4o-mini".
            HStack(spacing: 6) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if !model.detail.isEmpty {
                    Text("· \(model.detail)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            if isListening {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(timeString(Date().timeIntervalSince(model.startedAt)))
                        .font(Fonts.mono(12)).foregroundStyle(.white.opacity(0.7))
                        .monospacedDigit()
                }
                .padding(.leading, 6)
            }
        }
    }


    private var islandBackground: some View {
        ZStack {
            VaniVisualEffect(material: .hudWindow)
            LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x262634, alpha: 0.82)),
                                    Color(nsColor: NSColor(hex: 0x0C0D12, alpha: 0.90))],
                           startPoint: .top, endPoint: .bottom)
        }
        .clipShape(Capsule())
    }

    @ViewBuilder private var leading: some View {
        switch model.phase {
        case .idle:
            EmptyView()   // idle uses idleContent, not this
        case .listening(let command):
            VoiceDot(color: command ? VaniToken.warn : VaniToken.accent)
        case .transcribing, .cleaning:
            ThinkingDots()
        case .inserted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(VaniToken.good).font(.system(size: 20))
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 18))
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Animated bits

private struct VoiceDot: View {
    var color: Color
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.5), lineWidth: 2)
                .frame(width: 14, height: 14)
                .scaleEffect(on ? 2.2 : 0.7).opacity(on ? 0 : 0.8)
            Circle().fill(color).frame(width: 13, height: 13)
                .scaleEffect(on ? 1.18 : 1.0)
        }
        .frame(width: 22, height: 22)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

private struct Waveform: View {
    var level: CGFloat                    // live mic level 0…1
    // Per-bar weights give the silhouette shape; the live level scales the whole thing.
    private let weights: [CGFloat] = [0.35, 0.7, 0.5, 0.95, 0.45, 0.8, 0.3, 1.0, 0.5, 0.75,
                                      0.35, 0.85, 0.6, 0.95, 0.4, 0.7, 0.5, 0.8, 0.45, 0.65]
    var body: some View {
        // A gentle idle shimmer so it's alive even in silence, plus the real level on top.
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(weights.indices, id: \.self) { i in
                    let shimmer = 0.5 + 0.5 * sin(t * 6 + Double(i) * 0.7)   // 0…1
                    let idle: CGFloat = 4 + 2 * CGFloat(shimmer)
                    let active = idle + level * weights[i] * 18
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width: 2.5, height: min(22, active))
                }
            }
            .frame(height: 22)
            .animation(.easeOut(duration: 0.08), value: level)
        }
    }
}

private struct KeyCap: View {
    let glyph: String
    var body: some View {
        Text(glyph)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.95))
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }
}

private struct ThinkingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(VaniToken.accent)
                    .frame(width: 7, height: 7)
                    .opacity(on ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.18), value: on)
            }
        }
        .frame(width: 24, alignment: .leading)
        .onAppear { on = true }
    }
}

// MARK: - Sound cues

@MainActor
enum SoundCue {
    private static var enabled: Bool { SettingsStore.shared.playSound }
    static func start() { if enabled { NSSound(named: "Tink")?.play() } }
    static func done()  { if enabled { NSSound(named: "Pop")?.play() } }
    static func error() { if enabled { NSSound(named: "Basso")?.play() } }
}
