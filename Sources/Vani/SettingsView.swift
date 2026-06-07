import SwiftUI
import AppKit
import CoreGraphics
import FlowCore

/// Provider selection, hotkeys, and API-key entry. Values persist to app preferences.
struct SettingsView: View {
    private let store = SettingsStore.shared
    @ObservedObject private var app = AppState.shared

    @State private var sttChoice: STTChoice = SettingsStore.shared.sttChoice
    @State private var llmChoice: LLMChoice = SettingsStore.shared.llmChoice
    @State private var dictationHotkey: HotkeyTrigger = SettingsStore.shared.dictationHotkey
    @State private var commandHotkey: HotkeyTrigger = SettingsStore.shared.commandHotkey
    @State private var customDictationFlags: Int = Int(SettingsStore.shared.customDictationFlags.rawValue)
    @State private var customCommandFlags: Int = Int(SettingsStore.shared.customCommandFlags.rawValue)
    @State private var selectedModeID: String = SettingsStore.shared.selectedModeID
    @State private var customModesText: String = SettingsStore.shared.customModesText
    @State private var snippetsText: String = SettingsStore.shared.snippetsText
    @State private var powerEnabled: Bool = SettingsStore.shared.powerModeEnabled
    @State private var powerProfiles: [PowerProfile] = SettingsStore.shared.powerProfiles
    @State private var language: String = SettingsStore.shared.language
    @State private var vocabulary: String = SettingsStore.shared.customVocabulary
    @State private var learnedText: String = SettingsStore.shared.learnedTerms.joined(separator: ", ")
    @State private var openAIKey: String = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.openAI)
    @State private var groqKey: String = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.groq)
    @State private var anthropicKey: String = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.anthropic)
    @State private var openRouterKey: String = SettingsStore.shared.apiKey(for: SettingsStore.KeyAccount.openRouter)
    @State private var openRouterModel: String = SettingsStore.shared.openRouterModel
    @State private var openRouterSTTModel: String = SettingsStore.shared.openRouterSTTModel
    @State private var whisperBinaryPath: String = SettingsStore.shared.whisperBinaryPath
    @State private var whisperModelPath: String = SettingsStore.shared.whisperModelPath
    @State private var saved = false

    var body: some View {
        Form {
            Section("Providers") {
                Picker("Speech-to-text", selection: $sttChoice) {
                    ForEach(STTChoice.allCases) { Text($0.label).tag($0) }
                }
                if sttChoice == .openRouter {
                    TextField("OpenRouter STT model", text: $openRouterSTTModel)
                        .textFieldStyle(.roundedBorder)
                    Text("e.g. openai/gpt-4o-mini-transcribe, openai/gpt-4o-transcribe, openai/whisper-1")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if sttChoice == .parakeet {
                    HStack {
                        Button("Download model for offline use") { app.prepareParakeet() }
                        if !app.parakeetStatus.isEmpty {
                            Text(app.parakeetStatus).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Runs on the Neural Engine. After this one-time download it transcribes fully offline (no key). Cleanup still needs a cloud/local LLM; offline, Vani inserts the raw transcription.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if sttChoice == .localWhisper {
                    TextField("whisper-cli path", text: $whisperBinaryPath)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model path (ggml-*.bin)", text: $whisperModelPath)
                        .textFieldStyle(.roundedBorder)
                    Text("Install: brew install whisper-cpp, then download a ggml model. Fully offline — no key needed.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Picker("Cleanup model", selection: $llmChoice) {
                    ForEach(LLMChoice.allCases) { Text($0.label).tag($0) }
                }
                if llmChoice == .openRouter {
                    TextField("OpenRouter cleanup model", text: $openRouterModel)
                        .textFieldStyle(.roundedBorder)
                    Text("e.g. openai/gpt-4o-mini, anthropic/claude-3.5-haiku, google/gemini-flash-1.5")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if sttChoice == .openRouter && llmChoice == .openRouter {
                Section {
                    Label("Nice — one OpenRouter key powers both transcription and cleanup.",
                          systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(.green)
                }
            }

            Section("Writing") {
                Picker("Mode", selection: $selectedModeID) {
                    ForEach(WritingStyle.allCases) { Text($0.label).tag($0.rawValue) }
                    ForEach(parsedCustomModes) { Text($0.name).tag($0.id) }
                }
                Picker("Language", selection: $language) {
                    ForEach(Languages.all) { Text($0.name).tag($0.code) }
                }
                TextField("Custom vocabulary (names, jargon)", text: $vocabulary, axis: .vertical)
                    .lineLimit(2...4)
                Text("Comma-separated names/terms — used to prime transcription so it spells them right. Your macOS name and on-screen text are added automatically.")
                    .font(.caption2).foregroundStyle(.secondary)
                TextField("Learned words (auto-built; edit to prune)", text: $learnedText, axis: .vertical)
                    .lineLimit(1...3)
                Text("Built from \u{201C}Teach a Word\u{201D} / \u{201C}Correct Last Result\u{201D} in the menu.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Custom modes") {
                TextField("Name :: instruction (one per line)", text: $customModesText, axis: .vertical)
                    .lineLimit(2...6)
                Text("e.g.  Tweet :: Punchy, under 280 chars, no hashtags.\nThen pick it in the Mode dropdown above.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Text replacements / snippets") {
                TextField("trigger = replacement (one per line)", text: $snippetsText, axis: .vertical)
                    .lineLimit(2...6)
                Text("e.g.  my email = dinesh@example.com\nApplied to inserted text (case-insensitive).")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Power Mode (per-app)") {
                Toggle("Auto-switch mode by app", isOn: $powerEnabled)
                ForEach($powerProfiles) { $p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(p.appName).font(.callout).bold()
                            Spacer()
                            Button { powerProfiles.removeAll { $0.id == p.id } } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        Picker("Mode", selection: $p.modeID) {
                            ForEach(WritingStyle.allCases) { Text($0.label).tag($0.rawValue) }
                            ForEach(parsedCustomModes) { Text($0.name).tag($0.id) }
                        }
                        Picker("Language", selection: $p.language) {
                            ForEach(Languages.all) { Text($0.name).tag($0.code) }
                        }
                    }
                }
                Menu("Add app…") {
                    ForEach(addableApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") { addApp(app) }
                    }
                }
                Text("When you dictate in an app with a profile, Vani uses that mode/language automatically. (URL-based rules need Automation permission — later.)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Hotkeys (hold to talk)") {
                Picker("Dictation", selection: $dictationHotkey) {
                    ForEach(HotkeyTrigger.allCases.filter { $0 != .off }) { Text($0.label).tag($0) }
                }
                if dictationHotkey == .custom {
                    ShortcutRecorder(flagsRaw: $customDictationFlags)
                }
                Picker("Command", selection: $commandHotkey) {
                    ForEach(HotkeyTrigger.allCases) { Text($0.label).tag($0) }
                }
                if commandHotkey == .custom {
                    ShortcutRecorder(flagsRaw: $customCommandFlags)
                }
                Text("Dictation inserts your speech. Command: with text selected it edits the selection in place (\"make this concise\"); with nothing selected it answers your question in a floating popover. Give them different keys.")
                    .font(.caption2).foregroundStyle(.secondary)
                if commandHotkey != .off && commandHotkey == dictationHotkey {
                    Label("Dictation and Command use the same key — pick different ones.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("API keys") {
                SecureField("OpenAI key (sk-…)", text: $openAIKey)
                SecureField("Groq key (gsk_…)", text: $groqKey)
                SecureField("OpenRouter key (sk-or-…)", text: $openRouterKey)
                SecureField("Anthropic key (sk-ant-…)", text: $anthropicKey)
                Text("Bring your own keys — Vani calls providers directly and never proxies your audio or text through a server. Keys are saved locally in app preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                    if saved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }

    /// Running regular apps not already in a profile, for the "Add app…" menu.
    private var addableApps: [NSRunningApplication] {
        let existing = Set(powerProfiles.map { $0.bundleID })
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { app in
                guard let bid = app.bundleIdentifier, !existing.contains(bid),
                      (app.localizedName?.isEmpty == false) else { return false }
                return seen.insert(bid).inserted
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func addApp(_ app: NSRunningApplication) {
        guard let bid = app.bundleIdentifier else { return }
        powerProfiles.append(PowerProfile(bundleID: bid,
                                          appName: app.localizedName ?? bid,
                                          modeID: selectedModeID,
                                          language: ""))
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
        store.sttChoice = sttChoice
        store.llmChoice = llmChoice
        store.dictationHotkey = dictationHotkey
        store.commandHotkey = commandHotkey
        store.customDictationFlags = CGEventFlags(rawValue: UInt64(customDictationFlags))
        store.customCommandFlags = CGEventFlags(rawValue: UInt64(customCommandFlags))
        store.customModesText = customModesText
        store.snippetsText = snippetsText
        store.powerModeEnabled = powerEnabled
        store.powerProfiles = powerProfiles
        // If the selected mode no longer exists (renamed/removed), fall back to casual.
        let validIDs = Set(WritingStyle.allCases.map { $0.rawValue } + parsedCustomModes.map { $0.id })
        store.selectedModeID = validIDs.contains(selectedModeID) ? selectedModeID : WritingStyle.casual.rawValue
        store.language = language
        store.customVocabulary = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        store.learnedTerms = learnedText
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        store.openRouterModel = openRouterModel.trimmingCharacters(in: .whitespaces)
        store.openRouterSTTModel = openRouterSTTModel.trimmingCharacters(in: .whitespaces)
        store.whisperBinaryPath = whisperBinaryPath.trimmingCharacters(in: .whitespaces)
        store.whisperModelPath = expandTilde(whisperModelPath.trimmingCharacters(in: .whitespaces))
        store.setAPIKey(openAIKey, for: SettingsStore.KeyAccount.openAI)
        store.setAPIKey(groqKey, for: SettingsStore.KeyAccount.groq)
        store.setAPIKey(openRouterKey, for: SettingsStore.KeyAccount.openRouter)
        store.setAPIKey(anthropicKey, for: SettingsStore.KeyAccount.anthropic)

        // Re-apply hotkey bindings immediately.
        AppState.shared.reloadHotkeys()

        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
    }

    private func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
