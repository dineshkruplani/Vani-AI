import AppKit
import SwiftUI
import FlowCore

/// Hosts the onboarding wizard in a real window (menu-bar apps have no main window).
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.title = "Welcome to Vani"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView { [weak self] in self?.finish() })
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        Startup.applyDockPolicy(showInDock: SettingsStore.shared.showInDock)
    }
}

/// 7-step first-run wizard styled to the Vani design.
struct OnboardingView: View {
    let onFinish: () -> Void
    private let store = SettingsStore.shared

    enum Step: Int, CaseIterable { case welcome, permissions, pushToTalk, connect, style, tryIt, done }
    @State private var step: Step = .welcome

    @State private var selectedModeID = SettingsStore.shared.selectedModeID
    @State private var language = SettingsStore.shared.language
    @State private var hotkey = SettingsStore.shared.dictationHotkey
    @State private var openRouterKey = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.openRouter)
    @State private var micGranted = AudioRecorder.hasPermission

    @ObservedObject private var app = AppState.shared

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 44)
                    .padding(.top, 40)
                footer
            }
        }
        .frame(width: 600, height: 680)
        .tint(VaniToken.accent)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .permissions: permissions
        case .pushToTalk: pushToTalk
        case .connect: connect
        case .style: styleStep
        case .tryIt: tryIt
        case .done: done
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            AppIconMark(size: 92).floating()
            Text("Vani").font(Fonts.wordmark(34)).foregroundStyle(VaniToken.accent)
            Text("Your voice, written everywhere.")
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(VaniToken.text)
                .multilineTextAlignment(.center)
            Text("Hold a key, speak, and your words appear — cleaned up — in any app. Bring your own key; nothing is proxied through a server.")
                .font(.callout).foregroundStyle(VaniToken.text2)
                .multilineTextAlignment(.center).frame(maxWidth: 420)

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NEW MESSAGE").font(Fonts.mono(10)).foregroundStyle(VaniToken.text3)
                    TypewriterText(full: "I'll get back to you later today.", font: .system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(14)
            }
            .frame(width: 360)
            .padding(.top, 6)
        }
    }

    private var permissions: some View {
        VStack(spacing: 18) {
            PulseOrb().frame(width: 84, height: 84)
            title("Private by design", "Vani needs two permissions to work.")
            GlassCard {
                permissionRow("Microphone", "To hear what you say", granted: micGranted) {
                    Task { micGranted = await AudioRecorder.requestPermission() }
                }
                permissionRow("Accessibility", "For the global key and to type into apps",
                              granted: app.accessibilityGranted, last: true) {
                    app.openAccessibilitySettings()
                }
            }.frame(width: 420)
            GlassCard {
                Text("Your voice stays yours. Audio goes straight to your provider — never through our servers.")
                    .font(.caption).foregroundStyle(VaniToken.text2).padding(14)
            }.frame(width: 420)
        }
    }

    private var pushToTalk: some View {
        VStack(spacing: 18) {
            title("One key does it all", "Hold it to talk; release to insert.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                keyCard(.fn, "Fn", badge: nil)
                keyCard(.rightOption, "Right Option ⌥", badge: "Best")
                keyCard(.rightCommand, "Right Command ⌘", badge: nil)
                keyCard(.rightControl, "Right Control ⌃", badge: nil)
            }
            .frame(width: 420)
        }
    }

    private var connect: some View {
        VStack(spacing: 16) {
            title("Bring your own key", "OpenRouter powers both transcription and cleanup.")
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("sk-or-v1-…", text: $openRouterKey).textFieldStyle(.roundedBorder)
                    if !openRouterKey.isEmpty {
                        Label("Key looks good", systemImage: "checkmark.circle").font(.caption).foregroundStyle(VaniToken.good)
                    }
                    Text("Get one at openrouter.ai → Keys. You can skip and add it later in Settings.")
                        .font(.caption2).foregroundStyle(VaniToken.text3)
                }.padding(14)
            }.frame(width: 420)
        }
    }

    private var styleStep: some View {
        VStack(spacing: 16) {
            title("How should Vani write?", "Pick a tone — change it anytime.")
            ForEach(WritingStyle.allCases) { s in
                styleCard(s)
            }
            HStack {
                Text("Language").foregroundStyle(VaniToken.text2)
                Spacer()
                Picker("", selection: $language) { ForEach(Languages.all) { Text($0.name).tag($0.code) } }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
            }.frame(width: 420)
        }
    }

    private var tryIt: some View {
        VStack(spacing: 16) {
            title("Try it", "Tap, say a sentence with some \u{201C}um\u{201D}s, and watch it clean up.")
            Button(app.testRecording ? "Recording… tap to stop" : "Tap to record") {
                persist(); app.toggleTest()
            }
            .buttonStyle(.borderedProminent).controlSize(.large)

            if !app.testResult.isEmpty {
                GlassCard {
                    Text(app.testResult).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(width: 420)
            }
            if !app.detectedLanguage.isEmpty {
                Label("Detected language: \(languageName(app.detectedLanguage))", systemImage: "globe")
                    .font(.caption).foregroundStyle(VaniToken.text2)
                    .onAppear { language = app.detectedLanguage }
            }
            if !app.testError.isEmpty {
                Label(app.testError, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(VaniToken.good)
            Text("You're all set!").font(.system(size: 26, weight: .bold)).foregroundStyle(VaniToken.text)
            GlassCard {
                VStack(spacing: 0) {
                    recapRow("Push-to-talk", hotkey.label)
                    recapRow("Style", WritingStyle(rawValue: selectedModeID)?.label ?? "Custom")
                    recapRow("Provider", openRouterKey.isEmpty ? "Add later" : "OpenRouter", last: true)
                }
            }.frame(width: 360)
            Link("Follow on X", destination: URL(string: "https://x.com")!).buttonStyle(.bordered).padding(.top, 4)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step != .welcome { Button("Back") { back() }.buttonStyle(.plain) }
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule().fill(s == step ? VaniToken.accent : VaniToken.text3.opacity(0.4))
                        .frame(width: s == step ? 20 : 7, height: 7)
                }
            }
            Spacer()
            Button(primaryLabel) { step == .done ? complete() : next() }.buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private var primaryLabel: String {
        switch step { case .welcome: return "Set up"; case .done: return "Start using Vani"; default: return "Next" }
    }

    // MARK: Reusable bits

    private func title(_ t: String, _ s: String) -> some View {
        VStack(spacing: 6) {
            Text(t).font(.system(size: 22, weight: .bold)).foregroundStyle(VaniToken.text)
            Text(s).font(.callout).foregroundStyle(VaniToken.text2)
        }.multilineTextAlignment(.center)
    }

    private func permissionRow(_ name: String, _ sub: String, granted: Bool, last: Bool = false, action: @escaping () -> Void) -> some View {
        SettingRow(title: name, subtitle: sub, showDivider: !last) {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(VaniToken.good)
            } else {
                Button("Allow") { action() }
            }
        }
    }

    private func keyCard(_ t: HotkeyTrigger, _ label: String, badge: String?) -> some View {
        Button { hotkey = t } label: {
            HStack {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(VaniToken.text)
                Spacer()
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(VaniToken.accent, in: Capsule())
                }
            }
            .padding(12)
            .background(VaniToken.surface, in: RoundedRectangle(cornerRadius: VaniRadius.card))
            .overlay(RoundedRectangle(cornerRadius: VaniRadius.card)
                .strokeBorder(hotkey == t ? VaniToken.accent : VaniToken.border, lineWidth: hotkey == t ? 2 : 1))
        }.buttonStyle(.plain)
    }

    private func styleCard(_ s: WritingStyle) -> some View {
        Button { selectedModeID = s.rawValue } label: {
            HStack {
                Image(systemName: selectedModeID == s.rawValue ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedModeID == s.rawValue ? VaniToken.accent : VaniToken.text3)
                VStack(alignment: .leading) {
                    Text(s.label).font(.headline).foregroundStyle(VaniToken.text)
                    Text(s.blurb).font(.caption).foregroundStyle(VaniToken.text2)
                }
                Spacer()
            }
            .padding(12)
            .background(VaniToken.surface, in: RoundedRectangle(cornerRadius: VaniRadius.card))
            .overlay(RoundedRectangle(cornerRadius: VaniRadius.card)
                .strokeBorder(selectedModeID == s.rawValue ? VaniToken.accent : VaniToken.border,
                              lineWidth: selectedModeID == s.rawValue ? 2 : 1))
        }.buttonStyle(.plain).frame(width: 420)
    }

    private func recapRow(_ k: String, _ v: String, last: Bool = false) -> some View {
        SettingRow(title: k, showDivider: !last) {
            Text(v).font(.system(size: 13, weight: .medium)).foregroundStyle(VaniToken.accentText)
        }
    }

    private func languageName(_ code: String) -> String {
        Languages.all.first { $0.code == code }?.name ?? code.uppercased()
    }

    // MARK: Nav / persistence

    private func next() { persist(); if let n = Step(rawValue: step.rawValue + 1) { withAnimation { step = n } } }
    private func back() { if let p = Step(rawValue: step.rawValue - 1) { withAnimation { step = p } } }

    private func persist() {
        store.selectedModeID = selectedModeID
        store.language = language
        store.dictationHotkey = hotkey
        store.setAPIKey(openRouterKey, for: SettingsStore.KeyAccount.openRouter)
        if !openRouterKey.isEmpty { store.sttChoice = .openRouter; store.llmChoice = .openRouter }
        AppState.shared.reloadHotkeys()
    }

    private func complete() {
        persist()
        store.onboardingCompleted = true
        onFinish()
    }
}

// MARK: - Small decorative views

/// The Vani logo mark (single-stroke "va" + voice dot) on a gradient squircle.
struct AppIconMark: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x8E8BF2)),
                                              Color(nsColor: NSColor(hex: 0x524FCB))],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VaniMark().frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(nsColor: NSColor(hex: 0x524FCB)).opacity(0.5), radius: 16, y: 8)
    }
}

/// The logo glyph as a Shape-based path (matches the brand SVG).
struct VaniMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 100
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 40*s, y: 24*s))
                    p.addCurve(to: CGPoint(x: 67*s, y: 42*s),
                               control1: CGPoint(x: 40*s, y: 60*s), control2: CGPoint(x: 72*s, y: 62*s))
                    p.addCurve(to: CGPoint(x: 46*s, y: 51*s),
                               control1: CGPoint(x: 63*s, y: 27*s), control2: CGPoint(x: 45*s, y: 30*s))
                    p.addCurve(to: CGPoint(x: 62*s, y: 73*s),
                               control1: CGPoint(x: 47*s, y: 65*s), control2: CGPoint(x: 55*s, y: 71*s))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 8*s, lineCap: .round))
                Circle().fill(Color.white).frame(width: 17*s, height: 17*s)
                    .position(x: 33*s, y: 60*s)
            }
        }
    }
}

private struct PulseOrb: View {
    @State private var on = false
    var body: some View {
        ZStack {
            ForEach(0..<2) { i in
                Circle().stroke(VaniToken.accent.opacity(0.4), lineWidth: 2)
                    .scaleEffect(on ? 1.5 : 0.8).opacity(on ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.8).repeatForever().delay(Double(i) * 0.6), value: on)
            }
            Circle().fill(LinearGradient(colors: [VaniToken.accent, VaniToken.accentDeep],
                                         startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "mic.fill").foregroundStyle(.white).font(.system(size: 26)))
        }
        .onAppear { on = true }
    }
}

private struct TypewriterText: View {
    let full: String
    var font: Font = .body
    @State private var shown = ""
    var body: some View {
        Text(shown.isEmpty ? " " : shown).font(font).foregroundStyle(VaniToken.text)
            .onAppear { type() }
    }
    private func type() {
        shown = ""
        for (i, ch) in full.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.035) {
                shown.append(ch)
            }
        }
    }
}

private extension View {
    func floating() -> some View { modifier(FloatModifier()) }
}

private struct FloatModifier: ViewModifier {
    @State private var up = false
    func body(content: Content) -> some View {
        content.offset(y: up ? -6 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { up = true } }
    }
}
