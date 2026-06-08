import SwiftUI
import AppKit
import CoreGraphics
import FlowCore

/// Glass 6-tab settings matching the Vani design: icon-pill tab bar, uppercase
/// group labels, glass cards with rows + subtitles.
struct SettingsView: View {
    private let store = SettingsStore.shared
    @ObservedObject private var app = AppState.shared

    enum Tab: Hashable { case general, voice, providers, shortcuts, privacy, about }
    enum ProvidersMode: String, CaseIterable { case simple, advanced }

    @State private var tab: Tab = .general

    @State private var sttChoice = SettingsStore.shared.sttChoice
    @State private var llmChoice = SettingsStore.shared.llmChoice
    @State private var providersMode: ProvidersMode = .simple
    @State private var dictationHotkey = SettingsStore.shared.dictationHotkey
    @State private var commandHotkey = SettingsStore.shared.commandHotkey
    @State private var customDictationFlags = Int(SettingsStore.shared.customDictationFlags.rawValue)
    @State private var customCommandFlags = Int(SettingsStore.shared.customCommandFlags.rawValue)
    @State private var selectedModeID = SettingsStore.shared.selectedModeID
    @State private var customModesText = SettingsStore.shared.customModesText
    @State private var snippetsText = SettingsStore.shared.snippetsText
    @State private var powerEnabled = SettingsStore.shared.powerModeEnabled
    @State private var powerProfiles = SettingsStore.shared.powerProfiles
    @State private var language = SettingsStore.shared.language
    @State private var vocabItems = SettingsStore.shared.vocabularyList
    @State private var learnedText = SettingsStore.shared.learnedTerms.joined(separator: ", ")
    @State private var openAIKey = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.openAI)
    @State private var groqKey = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.groq)
    @State private var anthropicKey = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.anthropic)
    @State private var openRouterKey = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.openRouter)
    @State private var openRouterModel = SettingsStore.shared.openRouterModel
    @State private var openRouterSTTModel = SettingsStore.shared.openRouterSTTModel
    @State private var whisperBinaryPath = SettingsStore.shared.whisperBinaryPath
    @State private var whisperModelPath = SettingsStore.shared.whisperModelPath
    @State private var appTheme = SettingsStore.shared.appTheme
    @State private var showInDock = SettingsStore.shared.showInDock
    @State private var menuBarVisible = SettingsStore.shared.showMenuBarIcon
    @State private var launchAtLogin = Startup.isLoginItemEnabled
    @State private var historyEnabled = SettingsStore.shared.historyEnabled
    @State private var historyCount = SettingsStore.shared.history.count
    @State private var removeFiller = SettingsStore.shared.removeFiller
    @State private var autoPunct = SettingsStore.shared.autoPunctuation
    @State private var smartCaps = SettingsStore.shared.smartCaps
    @State private var screenContext = SettingsStore.shared.screenContextEnabled
    @State private var screenOCR = SettingsStore.shared.screenOCREnabled
    @State private var playSound = SettingsStore.shared.playSound
    @State private var floatingIndicator = SettingsStore.shared.showFloatingIndicator
    @State private var holdPrompt = SettingsStore.shared.showHoldPrompt
    @State private var diagnostics = SettingsStore.shared.diagnostics
    @State private var accentHex = SettingsStore.shared.accentHex
    @State private var saved = false

    private var accent: Color { Color(nsColor: NSColor(hex: accentHex)) }

    var body: some View {
        VStack(spacing: 0) {
            VaniTabBar(tabs: [
                (Tab.general, "General", "gearshape"),
                (Tab.voice, "Voice", "waveform"),
                (Tab.providers, "Providers", "cpu"),
                (Tab.shortcuts, "Shortcuts", "command"),
                (Tab.privacy, "Privacy", "lock.shield"),
                (Tab.about, "About", "info.circle"),
            ], selection: $tab)
            .padding(.top, 6)

            Divider().opacity(0.4)

            ScrollView {
                content.padding(20)
            }

            Divider().opacity(0.4)
            HStack {
                Spacer()
                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(VaniToken.good).font(.caption)
                }
                Button("Save") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 720, height: 600)
        .background(AuroraBackground())
        .tint(accent)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .general: general
        case .voice: voice
        case .providers: providers
        case .shortcuts: shortcuts
        case .privacy: privacy
        case .about: about
        }
    }

    // MARK: General

    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupLabel("Startup")
            GlassCard {
                SettingRow(title: "Launch at login") { sw($launchAtLogin) { Startup.setLoginItem($0) } }
                SettingRow(title: "Show in menu bar") { sw($menuBarVisible) { v in
                    store.showMenuBarIcon = v
                    if !v { showInDock = true; store.showInDock = true; Startup.applyDockPolicy(showInDock: true) }
                } }
                SettingRow(title: "Show in Dock", subtitle: "Keep Vani out of the way as a menu-bar app",
                           showDivider: false) { sw($showInDock) { Startup.applyDockPolicy(showInDock: $0) } }
            }
            GroupLabel("Appearance")
            GlassCard {
                SettingRow(title: "Theme") {
                    Picker("", selection: $appTheme) { ForEach(AppTheme.allCases) { Text($0.label).tag($0) } }
                        .labelsHidden().pickerStyle(.segmented).fixedSize()
                        .onChange(of: appTheme) { Appearance.apply(appTheme) }
                }
                SettingRow(title: "Accent color", showDivider: false) { AccentSwatches(selected: $accentHex) }
            }
            GroupLabel("Feedback")
            GlassCard {
                SettingRow(title: "Play sound on start / stop") { sw($playSound) }
                SettingRow(title: "Show floating indicator (HUD)") { sw($floatingIndicator) }
                SettingRow(title: "Show “Hold to talk” in text fields",
                           subtitle: "A small prompt appears when you click into any text box.",
                           showDivider: false) { sw($holdPrompt) }
            }
            GroupLabel("History")
            GlassCard {
                SettingRow(title: "Store dictation history") { sw($historyEnabled) }
                SettingRow(title: "\(historyCount) saved", showDivider: false) {
                    Button("Clear") { store.clearHistory(); historyCount = 0 }.disabled(historyCount == 0)
                }
            }
        }
    }

    // MARK: Voice

    private var voice: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupLabel("Writing style")
            GlassCard {
                SettingRow(title: "Style", subtitle: "How Vani phrases what you say") {
                    Picker("", selection: $selectedModeID) {
                        ForEach(WritingStyle.allCases) { Text($0.label).tag($0.rawValue) }
                        ForEach(parsedCustomModes) { Text($0.name).tag($0.id) }
                    }.labelsHidden().pickerStyle(.menu).fixedSize()
                }
                SettingRow(title: "Language", showDivider: false) {
                    Picker("", selection: $language) { ForEach(Languages.all) { Text($0.name).tag($0.code) } }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                }
            }
            GroupLabel("Cleanup")
            GlassCard {
                SettingRow(title: "Remove filler words") { sw($removeFiller) }
                SettingRow(title: "Automatic punctuation") { sw($autoPunct) }
                SettingRow(title: "Smart capitalization", showDivider: false) { sw($smartCaps) }
            }
            caption("Vani removes \u{201C}um\u{201D}s and false starts, then lightly formats — without changing your meaning.")

            GroupLabel("Context awareness")
            GlassCard {
                SettingRow(title: "Understand on-screen content",
                           subtitle: "Reads the active window (app, title, visible text) so the AI spells names right and matches context.",
                           showDivider: screenContext) { sw($screenContext) }
                if screenContext {
                    SettingRow(title: "Use screen OCR for unreadable apps",
                               subtitle: "Screenshots + reads the window when Accessibility can\u{2019}t. Needs Screen Recording permission.",
                               showDivider: false) { sw($screenOCR) }
                }
            }
            caption("Context is read on-device and sent only to your chosen provider with your dictation — never to us.")

            GroupLabel("Custom vocabulary")
            GlassCard {
                ChipField(items: $vocabItems).padding(12)
            }
            caption("Names/jargon to spell correctly. Your macOS name and on-screen text are added automatically.")

            GroupLabel("Custom modes")
            GlassCard {
                TextField("Name :: instruction (one per line)", text: $customModesText, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(2...5).padding(12)
            }
            GroupLabel("Text replacements")
            GlassCard {
                TextField("trigger = replacement (one per line)", text: $snippetsText, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(2...5).padding(12)
            }

            GroupLabel("Power Mode (per-app)")
            GlassCard {
                SettingRow(title: "Auto-switch mode by app", showDivider: !powerProfiles.isEmpty) { sw($powerEnabled) }
                ForEach($powerProfiles) { $p in
                    SettingRow(title: p.appName, showDivider: true) {
                        HStack(spacing: 6) {
                            Picker("", selection: $p.modeID) {
                                ForEach(WritingStyle.allCases) { Text($0.label).tag($0.rawValue) }
                                ForEach(parsedCustomModes) { Text($0.name).tag($0.id) }
                            }.labelsHidden().pickerStyle(.menu).fixedSize()
                            Button { powerProfiles.removeAll { $0.id == p.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                HStack {
                    Menu("Add app…") {
                        ForEach(addableApps, id: \.bundleIdentifier) { a in
                            Button(a.localizedName ?? a.bundleIdentifier ?? "App") { addApp(a) }
                        }
                    }.fixedSize()
                    Spacer()
                }.padding(12)
            }
        }
    }

    // MARK: Providers

    private var providers: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("", selection: $providersMode) {
                Text("Simple").tag(ProvidersMode.simple)
                Text("Advanced").tag(ProvidersMode.advanced)
            }.labelsHidden().pickerStyle(.segmented)

            if providersMode == .simple {
                GroupLabel("One key, everything works")
                GlassCard {
                    SettingRow(title: "OpenRouter key", showDivider: false) {
                        SecureField("sk-or-…", text: $openRouterKey).textFieldStyle(.plain).frame(width: 200)
                    }
                }
                if !openRouterKey.isEmpty {
                    Label("Connected — Whisper + GPT-4o-mini", systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(VaniToken.good)
                }
                caption("OpenRouter powers both transcription and cleanup. Get a key at openrouter.ai → Keys.")
            } else {
                GroupLabel("Speech-to-text")
                GlassCard {
                    SettingRow(title: "Provider", showDivider: [.openRouter, .parakeet, .localWhisper].contains(sttChoice)) {
                        Picker("", selection: $sttChoice) { ForEach(STTChoice.allCases) { Text($0.label).tag($0) } }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    if sttChoice == .openRouter {
                        SettingRow(title: "Model", showDivider: false) {
                            TextField("openai/gpt-4o-mini-transcribe", text: $openRouterSTTModel).textFieldStyle(.plain).frame(width: 220)
                        }
                    }
                    if sttChoice == .parakeet {
                        SettingRow(title: app.parakeetStatus.isEmpty ? "On-device, no key" : app.parakeetStatus, showDivider: false) {
                            Button("Download") { app.prepareParakeet() }
                        }
                    }
                    if sttChoice == .localWhisper {
                        SettingRow(title: "whisper-cli") { TextField("path", text: $whisperBinaryPath).textFieldStyle(.plain).frame(width: 220) }
                        SettingRow(title: "Model", showDivider: false) { TextField("ggml-*.bin", text: $whisperModelPath).textFieldStyle(.plain).frame(width: 220) }
                    }
                }
                GroupLabel("Cleanup")
                GlassCard {
                    SettingRow(title: "Provider", showDivider: llmChoice == .openRouter) {
                        Picker("", selection: $llmChoice) { ForEach(LLMChoice.allCases) { Text($0.label).tag($0) } }
                            .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    if llmChoice == .openRouter {
                        SettingRow(title: "Model", showDivider: false) {
                            TextField("openai/gpt-4o-mini", text: $openRouterModel).textFieldStyle(.plain).frame(width: 220)
                        }
                    }
                }
                GroupLabel("API keys")
                GlassCard {
                    keyRow("OpenAI", "sk-…", $openAIKey)
                    keyRow("Groq", "gsk_…", $groqKey)
                    keyRow("OpenRouter", "sk-or-…", $openRouterKey)
                    keyRow("Anthropic", "sk-ant-…", $anthropicKey, last: true)
                }
            }
        }
    }

    private func keyRow(_ name: String, _ ph: String, _ b: Binding<String>, last: Bool = false) -> some View {
        SettingRow(title: name, showDivider: !last) {
            SecureField(ph, text: b).textFieldStyle(.plain).frame(width: 200)
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupLabel("Hold to talk")
            GlassCard {
                SettingRow(title: "Dictation", showDivider: dictationHotkey == .custom) {
                    Picker("", selection: $dictationHotkey) {
                        ForEach(HotkeyTrigger.allCases.filter { $0 != .off }) { Text($0.label).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).fixedSize()
                }
                if dictationHotkey == .custom {
                    SettingRow(title: "Combo") { ShortcutRecorder(flagsRaw: $customDictationFlags) }
                }
                SettingRow(title: "Command", showDivider: commandHotkey == .custom) {
                    Picker("", selection: $commandHotkey) {
                        ForEach(HotkeyTrigger.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).fixedSize()
                }
                if commandHotkey == .custom {
                    SettingRow(title: "Combo", showDivider: false) { ShortcutRecorder(flagsRaw: $customCommandFlags) }
                }
            }
            if commandHotkey != .off && commandHotkey == dictationHotkey {
                Label("Pick different keys for Dictation and Command.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            caption("Hold to talk, or double-tap to go hands-free (single tap to stop). Command edits selected text in place, or answers a question when nothing is selected.")
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Your voice never touches our servers.", systemImage: "lock.shield").font(.headline)
                    Text("Audio and text go directly to the provider you choose — or stay fully on-device with Parakeet / whisper.cpp. There is no Vani server.")
                        .font(.caption).foregroundStyle(VaniToken.text2)
                }.padding(14)
            }
            GroupLabel("Data")
            GlassCard {
                SettingRow(title: "Store dictation history") { sw($historyEnabled) }
                SettingRow(title: "Anonymous diagnostics", subtitle: "Off — Vani collects nothing today") { sw($diagnostics) }
                SettingRow(title: "Keys stored locally in app preferences", showDivider: false) {
                    Button("Clear History") { store.clearHistory(); historyCount = 0 }.disabled(historyCount == 0)
                }
            }
        }
    }

    // MARK: About

    private var about: some View {
        VStack(spacing: 12) {
            Text("Vani").font(Fonts.wordmark(40)).foregroundStyle(accent)
            Text("Version 0.2").font(Fonts.mono(12)).foregroundStyle(VaniToken.text3)
            Text("Your voice, written everywhere.").font(.callout).foregroundStyle(VaniToken.text2)
            (Text("from the Sanskrit ") + Text("vāṇī").font(Fonts.serif(15)) + Text(" — voice / speech."))
                .font(.callout).foregroundStyle(VaniToken.text2)
            HStack {
                Link("Follow on X", destination: URL(string: "https://x.com")!).buttonStyle(.bordered)
                Button("Open Setup Guide") { OnboardingWindowController.shared.show() }.buttonStyle(.bordered)
            }.padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Bits

    private func sw(_ b: Binding<Bool>, _ onChange: ((Bool) -> Void)? = nil) -> some View {
        Toggle("", isOn: b).labelsHidden().toggleStyle(.switch).tint(accent)
            .onChange(of: b.wrappedValue) { onChange?(b.wrappedValue) }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(VaniToken.text3).padding(.horizontal, 4)
    }

    private var addableApps: [NSRunningApplication] {
        let existing = Set(powerProfiles.map { $0.bundleID })
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { a in
                guard let bid = a.bundleIdentifier, !existing.contains(bid),
                      (a.localizedName?.isEmpty == false) else { return false }
                return seen.insert(bid).inserted
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func addApp(_ a: NSRunningApplication) {
        guard let bid = a.bundleIdentifier else { return }
        powerProfiles.append(PowerProfile(bundleID: bid, appName: a.localizedName ?? bid,
                                          modeID: selectedModeID, language: ""))
    }

    private var parsedCustomModes: [PromptMode] {
        customModesText.split(separator: "\n").compactMap { line in
            guard let sep = line.range(of: "::") else { return nil }
            let name = line[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
            let instruction = line[sep.upperBound...].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : PromptMode(name: name, instruction: instruction)
        }
    }

    private func save() {
        store.appTheme = appTheme
        store.showInDock = showInDock
        store.showMenuBarIcon = menuBarVisible
        store.historyEnabled = historyEnabled
        store.removeFiller = removeFiller
        store.autoPunctuation = autoPunct
        store.smartCaps = smartCaps
        store.screenContextEnabled = screenContext
        store.screenOCREnabled = screenOCR
        store.playSound = playSound
        store.showFloatingIndicator = floatingIndicator
        store.showHoldPrompt = holdPrompt
        store.diagnostics = diagnostics
        store.accentHex = accentHex
        if providersMode == .simple {
            store.sttChoice = .openRouter; store.llmChoice = .openRouter
        } else {
            store.sttChoice = sttChoice; store.llmChoice = llmChoice
        }
        store.dictationHotkey = dictationHotkey
        store.commandHotkey = commandHotkey
        store.customDictationFlags = CGEventFlags(rawValue: UInt64(customDictationFlags))
        store.customCommandFlags = CGEventFlags(rawValue: UInt64(customCommandFlags))
        store.customModesText = customModesText
        store.snippetsText = snippetsText
        store.powerModeEnabled = powerEnabled
        store.powerProfiles = powerProfiles
        let validIDs = Set(WritingStyle.allCases.map { $0.rawValue } + parsedCustomModes.map { $0.id })
        store.selectedModeID = validIDs.contains(selectedModeID) ? selectedModeID : WritingStyle.casual.rawValue
        store.language = language
        store.vocabularyList = vocabItems
        store.learnedTerms = learnedText
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        store.openRouterModel = openRouterModel.trimmingCharacters(in: .whitespaces)
        store.openRouterSTTModel = openRouterSTTModel.trimmingCharacters(in: .whitespaces)
        store.whisperBinaryPath = whisperBinaryPath.trimmingCharacters(in: .whitespaces)
        store.whisperModelPath = (whisperModelPath.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        store.setAPIKey(openAIKey, for: SettingsStore.KeyAccount.openAI)
        store.setAPIKey(groqKey, for: SettingsStore.KeyAccount.groq)
        store.setAPIKey(openRouterKey, for: SettingsStore.KeyAccount.openRouter)
        store.setAPIKey(anthropicKey, for: SettingsStore.KeyAccount.anthropic)

        AppState.shared.reloadHotkeys()
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }
}
