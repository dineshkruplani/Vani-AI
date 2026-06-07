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
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Welcome to Vani"
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(onFinish: { [weak self] in
                self?.finish()
            }))
            window = w
        }
        // Become a regular app while onboarding so the window can take focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
    }

    // Restore menu-bar-only mode whenever the window closes (button or red X).
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Multi-step first-run wizard.
struct OnboardingView: View {
    let onFinish: () -> Void
    private let store = SettingsStore.shared

    enum Step: Int, CaseIterable { case welcome, profile, apiKey, test, shortcut, done }
    @State private var step: Step = .welcome

    // Bound to settings, persisted as the user advances.
    @State private var style = SettingsStore.shared.writingStyle
    @State private var language = SettingsStore.shared.language
    @State private var openRouterKey = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.openRouter)
    @State private var hotkey = SettingsStore.shared.dictationHotkey
    @State private var commandHotkey = SettingsStore.shared.commandHotkey
    @State private var vocabulary = SettingsStore.shared.customVocabulary

    @ObservedObject private var app = AppState.shared

    var body: some View {
        ZStack {
            VisualEffectFill().ignoresSafeArea()
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.top, 36)
                footer
            }
        }
        .frame(width: 560, height: 640)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:  welcomeStep
        case .profile:  profileStep
        case .apiKey:   apiKeyStep
        case .test:     testStep
        case .shortcut: shortcutStep
        case .done:     doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to Vani").font(.largeTitle.bold())
            Text("Hold a key, speak, and your words appear — cleaned up — in any app. Bring your own API key; nothing is proxied through a server.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            VStack(spacing: 10) {
                stubSignIn("apple.logo", "Continue with Apple")
                stubSignIn("globe", "Continue with Google")
                Text("Accounts are coming soon — set up locally for now.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    private func stubSignIn(_ icon: String, _ title: String) -> some View {
        Button { /* auth later */ next() } label: {
            HStack { Image(systemName: icon); Text(title) }
                .frame(maxWidth: 280)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .disabled(true) // placeholder until real auth exists
        .opacity(0.55)
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle("Your writing style", "Pick how Vani should phrase what you say.")
            ForEach(WritingStyle.allCases) { s in
                Button { style = s } label: {
                    HStack {
                        Image(systemName: style == s ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading) {
                            Text(s.label).font(.headline)
                            Text(s.blurb).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.quaternary.opacity(style == s ? 0.6 : 0.2), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Picker("Language", selection: $language) {
                ForEach(Languages.all) { Text($0.name).tag($0.code) }
            }
            .padding(.top, 4)
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("Add your API key", "Optional now — you can add it later in Settings. OpenRouter works for both transcription and cleanup with one key.")
            SecureField("OpenRouter key (sk-or-…)", text: $openRouterKey)
                .textFieldStyle(.roundedBorder)
            Text("Get one at openrouter.ai → Keys. Vani calls it directly; your audio/text never touch our servers.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var testStep: some View {
        VStack(spacing: 18) {
            stepTitle("Try it", "Hold the button, say a sentence with some \"um\"s, and watch it get cleaned up.")
            Button(app.testRecording ? "Recording… tap to stop" : "Tap to record") {
                persist() // make sure key/style/language are saved before testing
                app.toggleTest()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !app.testResult.isEmpty {
                Text(app.testResult)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
            if !app.detectedLanguage.isEmpty {
                Label("Detected language: \(languageName(app.detectedLanguage)) — set automatically.",
                      systemImage: "globe")
                    .font(.caption).foregroundStyle(.secondary)
                    .onAppear { language = app.detectedLanguage }
            }
            if !app.testError.isEmpty {
                Label(app.testError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !app.accessibilityGranted {
                Button("Grant Accessibility (needed to type into apps)") {
                    app.openAccessibilitySettings()
                }
                .font(.caption)
            }
        }
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("Choose your hotkeys", "Hold to talk. Right Option is the most reliable. Command is optional — set it to a different key to edit selected text or ask questions.")
            Picker("Dictation", selection: $hotkey) {
                ForEach(HotkeyTrigger.allCases.filter { $0 != .off && $0 != .custom }) { Text($0.label).tag($0) }
            }
            Picker("Command (optional)", selection: $commandHotkey) {
                ForEach(HotkeyTrigger.allCases.filter { $0 != .custom }) { Text($0.label).tag($0) }
            }
            Text("Want a custom modifier combo (e.g. ⌃⌥)? Set it later in Settings.")
                .font(.caption2).foregroundStyle(.secondary)
            if commandHotkey != .off && commandHotkey == hotkey {
                Label("Pick a different key for Command.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
            Text("You're all set!").font(.largeTitle.bold())
            Text("Hold \(hotkey.label) anywhere and start talking. Select text first to give an edit command (\"make this concise\").")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            Link("Follow us on X", destination: URL(string: "https://x.com")!)
                .buttonStyle(.bordered)
        }
    }

    // MARK: Footer / nav

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { back() }.buttonStyle(.plain)
            }
            Spacer()
            ForEach(Step.allCases, id: \.rawValue) { s in
                Circle().fill(s == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
            Spacer()
            Button(step == .done ? "Get Started" : "Next") {
                step == .done ? complete() : next()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private func languageName(_ code: String) -> String {
        Languages.all.first { $0.code == code }?.name ?? code.uppercased()
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func next() {
        persist()
        if let n = Step(rawValue: step.rawValue + 1) { withAnimation { step = n } }
    }
    private func back() {
        if let p = Step(rawValue: step.rawValue - 1) { withAnimation { step = p } }
    }

    private func persist() {
        store.selectedModeID = style.rawValue
        store.language = language
        store.dictationHotkey = hotkey
        store.commandHotkey = commandHotkey
        store.customVocabulary = vocabulary
        store.setAPIKey(openRouterKey, for: SettingsStore.KeyAccount.openRouter)
        // If they pasted an OpenRouter key, default both providers to OpenRouter.
        if !openRouterKey.isEmpty {
            store.sttChoice = .openRouter
            store.llmChoice = .openRouter
        }
        AppState.shared.reloadHotkeys()
    }

    private func complete() {
        persist()
        store.onboardingCompleted = true
        onFinish()
    }
}

/// Full-bleed vibrancy background for the wizard ("Liquid Glass" approximation).
private struct VisualEffectFill: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
