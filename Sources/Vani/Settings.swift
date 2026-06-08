import Foundation
import CoreGraphics
import FlowCore

/// A user-defined writing mode: a name + a free-text instruction appended to the cleanup prompt.
struct PromptMode: Codable, Identifiable, Hashable {
    var name: String
    var instruction: String
    var id: String { "custom:\(name)" }
}

/// A recorded dictation result (for the History view).
struct HistoryEntry: Codable, Identifiable, Hashable {
    var text: String
    var date: Date
    var id: Date { date }
}

/// Power Mode: per-app overrides applied automatically based on the frontmost app.
struct PowerProfile: Codable, Identifiable, Hashable {
    var bundleID: String
    var appName: String
    var modeID: String       // built-in WritingStyle rawValue or "custom:<name>"
    var language: String     // "" = inherit the global language
    var id: String { bundleID }
}

/// Supported transcription languages ("" = auto-detect).
struct LanguageOption: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

enum Languages {
    static let all: [LanguageOption] = [
        .init(code: "", name: "Auto-detect"),
        .init(code: "en", name: "English"),
        .init(code: "es", name: "Spanish"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "it", name: "Italian"),
        .init(code: "pt", name: "Portuguese"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "hi", name: "Hindi"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "ko", name: "Korean"),
        .init(code: "zh", name: "Chinese"),
        .init(code: "ar", name: "Arabic"),
        .init(code: "ru", name: "Russian"),
    ]
}

/// Which providers the user has selected. MVP defaults to OpenAI for both.
enum STTChoice: String, CaseIterable, Identifiable {
    case openAI, openRouter, groq, parakeet, localWhisper
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openAI: return "OpenAI (whisper-1)"
        case .openRouter: return "OpenRouter (whisper)"
        case .groq: return "Groq (whisper-large-v3-turbo)"
        case .parakeet: return "Local (Parakeet — fast, on-device)"
        case .localWhisper: return "Local (whisper.cpp — offline)"
        }
    }
}

enum LLMChoice: String, CaseIterable, Identifiable {
    case openAI, openRouter, groq, anthropic, ollama
    var id: String { rawValue }
    var label: String {
        switch self {
        case .openAI: return "OpenAI (gpt-4o-mini)"
        case .openRouter: return "OpenRouter (any model)"
        case .groq: return "Groq (llama-3.3-70b)"
        case .anthropic: return "Anthropic (claude-haiku-4-5)"
        case .ollama: return "Local (Ollama)"
        }
    }
}

/// Non-secret preferences in UserDefaults; API keys live in the Keychain.
final class SettingsStore {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let stt = "sttChoice"
        static let llm = "llmChoice"
        static let openRouterModel = "openRouterModel"
        static let openRouterSTTModel = "openRouterSTTModel"
        static let dictationHotkey = "dictationHotkey"
        static let commandHotkey = "commandHotkey"
        static let whisperBinary = "whisperBinaryPath"
        static let whisperModel = "whisperModelPath"
        static let writingStyle = "writingStyle"
        static let language = "language"
        static let vocabulary = "customVocabulary"
        static let onboardingDone = "onboardingCompleted"
        static let learnedTerms = "learnedTerms"
        static let customDictationFlags = "customDictationFlags"
        static let customCommandFlags = "customCommandFlags"
        static let selectedModeID = "selectedModeID"
        static let customModes = "customModes"
        static let snippets = "snippetsText"
        static let powerEnabled = "powerModeEnabled"
        static let powerProfiles = "powerProfiles"
        static let appTheme = "appTheme"
        static let showInDock = "showInDock"
        static let historyEnabled = "historyEnabled"
        static let history = "history"
        static let removeFiller = "cleanupRemoveFiller"
        static let autoPunctuation = "cleanupAutoPunctuation"
        static let smartCaps = "cleanupSmartCaps"
        static let playSound = "playSound"
        static let showMenuBar = "showMenuBarIcon"
        static let accentHex = "accentHex"
        static let floatingIndicator = "showFloatingIndicator"
        static let holdPrompt = "showHoldPrompt"
        static let diagnostics = "anonymousDiagnostics"
        static let screenContext = "screenContextEnabled"
        static let visionContext = "visionContextEnabled"
        static let visionModel = "visionModel"
    }

    // Transient per-dictation overrides (set by Power Mode at capture time; not persisted).
    var overrideModeID: String?
    var overrideLanguage: String?

    // MARK: - Appearance / startup / history

    var appTheme: AppTheme {
        get { AppTheme(rawValue: defaults.string(forKey: Key.appTheme) ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: Key.appTheme) }
    }

    var showInDock: Bool {
        get { defaults.bool(forKey: Key.showInDock) }
        set { defaults.set(newValue, forKey: Key.showInDock) }
    }

    /// History defaults ON unless explicitly disabled.
    var historyEnabled: Bool {
        get { defaults.object(forKey: Key.historyEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.historyEnabled) }
    }

    // Cleanup toggles (default ON — the base prompt already does all three).
    private func boolDefaultTrue(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
    var removeFiller: Bool { get { boolDefaultTrue(Key.removeFiller) } set { defaults.set(newValue, forKey: Key.removeFiller) } }
    var autoPunctuation: Bool { get { boolDefaultTrue(Key.autoPunctuation) } set { defaults.set(newValue, forKey: Key.autoPunctuation) } }
    var smartCaps: Bool { get { boolDefaultTrue(Key.smartCaps) } set { defaults.set(newValue, forKey: Key.smartCaps) } }
    var playSound: Bool { get { boolDefaultTrue(Key.playSound) } set { defaults.set(newValue, forKey: Key.playSound) } }
    var showMenuBarIcon: Bool { get { boolDefaultTrue(Key.showMenuBar) } set { defaults.set(newValue, forKey: Key.showMenuBar) } }
    var showFloatingIndicator: Bool { get { boolDefaultTrue(Key.floatingIndicator) } set { defaults.set(newValue, forKey: Key.floatingIndicator) } }
    /// Show the "Hold ⌥ to talk" prompt when a text field is focused in any app.
    var showHoldPrompt: Bool { get { boolDefaultTrue(Key.holdPrompt) } set { defaults.set(newValue, forKey: Key.holdPrompt) } }
    /// Read the active window (app, title, visible text) and give it to the AI as context.
    var screenContextEnabled: Bool { get { boolDefaultTrue(Key.screenContext) } set { defaults.set(newValue, forKey: Key.screenContext) } }
    /// Opt-in: screenshot the active window and have a vision model distill context
    /// (needs Screen Recording + an OpenRouter key). Replaces the old local-OCR tier.
    var visionContextEnabled: Bool { get { defaults.bool(forKey: Key.visionContext) } set { defaults.set(newValue, forKey: Key.visionContext) } }
    var visionModel: String {
        get { let v = defaults.string(forKey: Key.visionModel) ?? ""; return v.isEmpty ? "openai/gpt-4o-mini" : v }
        set { defaults.set(newValue, forKey: Key.visionModel) }
    }
    var diagnostics: Bool { get { defaults.bool(forKey: Key.diagnostics) } set { defaults.set(newValue, forKey: Key.diagnostics) } }

    var accentHex: UInt32 {
        get { UInt32(defaults.object(forKey: Key.accentHex) as? Int ?? 0x6F6BE0) }
        set { defaults.set(Int(newValue), forKey: Key.accentHex) }
    }

    /// Vocabulary as a list (chip UI) backed by the comma-separated string.
    var vocabularyList: [String] {
        get {
            customVocabulary.split(whereSeparator: { ",;\n".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        set { customVocabulary = newValue.joined(separator: ", ") }
    }

    /// Extra cleanup instructions when a default behavior is turned OFF.
    private var cleanupInstruction: String {
        var notes: [String] = []
        if !removeFiller { notes.append("Keep filler words (um, uh, like) as spoken.") }
        if !autoPunctuation { notes.append("Do not add or change punctuation.") }
        if !smartCaps { notes.append("Do not change capitalization.") }
        return notes.joined(separator: " ")
    }

    var history: [HistoryEntry] {
        get {
            guard let data = defaults.data(forKey: Key.history),
                  let items = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
            return items
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.history) }
    }

    func addHistory(_ text: String) {
        guard historyEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = history
        items.insert(HistoryEntry(text: trimmed, date: Date()), at: 0)
        if items.count > 100 { items = Array(items.prefix(100)) }
        history = items
    }

    func clearHistory() { defaults.removeObject(forKey: Key.history) }

    // Keychain accounts.
    enum KeyAccount {
        static let openAI = "openai"
        static let groq = "groq"
        static let anthropic = "anthropic"
        static let openRouter = "openrouter"
    }

    var sttChoice: STTChoice {
        get { STTChoice(rawValue: defaults.string(forKey: Key.stt) ?? "") ?? .openAI }
        set { defaults.set(newValue.rawValue, forKey: Key.stt) }
    }

    var llmChoice: LLMChoice {
        get { LLMChoice(rawValue: defaults.string(forKey: Key.llm) ?? "") ?? .openAI }
        set { defaults.set(newValue.rawValue, forKey: Key.llm) }
    }

    var openRouterModel: String {
        get {
            let v = defaults.string(forKey: Key.openRouterModel) ?? ""
            return v.isEmpty ? "openai/gpt-4o-mini" : v
        }
        set { defaults.set(newValue, forKey: Key.openRouterModel) }
    }

    var openRouterSTTModel: String {
        get {
            let v = defaults.string(forKey: Key.openRouterSTTModel) ?? ""
            return v.isEmpty ? "openai/gpt-4o-mini-transcribe" : v
        }
        set { defaults.set(newValue, forKey: Key.openRouterSTTModel) }
    }

    /// Short, friendly name of the active cleanup model — shown in the HUD
    /// ("Cleaning up · gpt-4o-mini"). Strips any "vendor/" prefix.
    var cleanupModelDisplay: String {
        let raw: String
        switch llmChoice {
        case .openAI:    raw = "gpt-4o-mini"
        case .openRouter: raw = openRouterModel
        case .groq:      raw = "llama-3.3-70b"
        case .anthropic: raw = "claude-haiku-4.5"
        case .ollama:    raw = "llama3.1:8b"
        }
        return raw.split(separator: "/").last.map(String.init) ?? raw
    }

    var dictationHotkey: HotkeyTrigger {
        get { HotkeyTrigger(rawValue: defaults.string(forKey: Key.dictationHotkey) ?? "") ?? .fn }
        set { defaults.set(newValue.rawValue, forKey: Key.dictationHotkey) }
    }

    var commandHotkey: HotkeyTrigger {
        get { HotkeyTrigger(rawValue: defaults.string(forKey: Key.commandHotkey) ?? "") ?? .off }
        set { defaults.set(newValue.rawValue, forKey: Key.commandHotkey) }
    }

    /// Modifier set for a custom dictation combo (CGEventFlags rawValue).
    var customDictationFlags: CGEventFlags {
        get { CGEventFlags(rawValue: UInt64(defaults.integer(forKey: Key.customDictationFlags))) }
        set { defaults.set(Int(newValue.rawValue), forKey: Key.customDictationFlags) }
    }

    var customCommandFlags: CGEventFlags {
        get { CGEventFlags(rawValue: UInt64(defaults.integer(forKey: Key.customCommandFlags))) }
        set { defaults.set(Int(newValue.rawValue), forKey: Key.customCommandFlags) }
    }

    var whisperBinaryPath: String {
        get {
            let v = defaults.string(forKey: Key.whisperBinary) ?? ""
            return v.isEmpty ? "/opt/homebrew/bin/whisper-cli" : v
        }
        set { defaults.set(newValue, forKey: Key.whisperBinary) }
    }

    var whisperModelPath: String {
        get { defaults.string(forKey: Key.whisperModel) ?? "" }
        set { defaults.set(newValue, forKey: Key.whisperModel) }
    }

    var writingStyle: WritingStyle {
        get { WritingStyle(rawValue: defaults.string(forKey: Key.writingStyle) ?? "") ?? .casual }
        set { defaults.set(newValue.rawValue, forKey: Key.writingStyle) }
    }

    /// Selected mode id: a built-in WritingStyle rawValue ("formal"/"casual"/"superCasual")
    /// or a custom mode id ("custom:<name>").
    var selectedModeID: String {
        get { defaults.string(forKey: Key.selectedModeID) ?? WritingStyle.casual.rawValue }
        set { defaults.set(newValue, forKey: Key.selectedModeID) }
    }

    /// Raw "Name :: instruction" lines defining custom modes.
    var customModesText: String {
        get { defaults.string(forKey: Key.customModes) ?? "" }
        set { defaults.set(newValue, forKey: Key.customModes) }
    }

    var customModes: [PromptMode] {
        customModesText.split(separator: "\n").compactMap { line in
            guard let sep = line.range(of: "::") else { return nil }
            let name = line[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
            let instruction = line[sep.upperBound...].trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : PromptMode(name: name, instruction: instruction)
        }
    }

    /// The cleanup-prompt instruction for the active mode (Power Mode override wins),
    /// plus any cleanup-toggle overrides.
    var resolvedStyleInstruction: String {
        let id = overrideModeID ?? selectedModeID
        let base: String
        if let style = WritingStyle(rawValue: id) { base = style.instruction }
        else if let mode = customModes.first(where: { $0.id == id }) { base = mode.instruction }
        else { base = WritingStyle.casual.instruction }
        let cleanup = cleanupInstruction
        return cleanup.isEmpty ? base : "\(base) \(cleanup)"
    }

    // MARK: - Power Mode

    var powerModeEnabled: Bool {
        get { defaults.bool(forKey: Key.powerEnabled) }
        set { defaults.set(newValue, forKey: Key.powerEnabled) }
    }

    var powerProfiles: [PowerProfile] {
        get {
            guard let data = defaults.data(forKey: Key.powerProfiles),
                  let p = try? JSONDecoder().decode([PowerProfile].self, from: data) else { return [] }
            return p
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.powerProfiles) }
    }

    func powerProfile(forBundleID bundleID: String) -> PowerProfile? {
        powerProfiles.first { $0.bundleID == bundleID }
    }

    /// Raw "trigger = replacement" lines for snippets/text-replacements.
    var snippetsText: String {
        get { defaults.string(forKey: Key.snippets) ?? "" }
        set { defaults.set(newValue, forKey: Key.snippets) }
    }

    /// Parse snippets into ordered (from, to) pairs.
    func snippetPairs() -> [(from: String, to: String)] {
        snippetsText.split(separator: "\n").compactMap { line in
            guard let eq = line.firstIndex(of: "=") else { return nil }
            let from = line[..<eq].trimmingCharacters(in: .whitespaces)
            let to = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            return from.isEmpty ? nil : (from: from, to: to)
        }
    }

    /// ISO-639-1 language code for transcription; "" = auto-detect.
    var language: String {
        get { defaults.string(forKey: Key.language) ?? "" }
        set { defaults.set(newValue, forKey: Key.language) }
    }

    /// User's custom words/names/jargon, used to prime Whisper for accuracy.
    var customVocabulary: String {
        get { defaults.string(forKey: Key.vocabulary) ?? "" }
        set { defaults.set(newValue, forKey: Key.vocabulary) }
    }

    var onboardingCompleted: Bool {
        get { defaults.bool(forKey: Key.onboardingDone) }
        set { defaults.set(newValue, forKey: Key.onboardingDone) }
    }

    /// Auto-learned correct spellings (from "Teach a word" / "Correct last").
    var learnedTerms: [String] {
        get { defaults.stringArray(forKey: Key.learnedTerms) ?? [] }
        set { defaults.set(newValue, forKey: Key.learnedTerms) }
    }

    private var sttLanguage: String? {
        let l = (overrideLanguage ?? language).trimmingCharacters(in: .whitespacesAndNewlines)
        return l.isEmpty ? nil : l
    }

    /// Assemble the Whisper priming prompt: preceding on-screen text + a glossary of
    /// the user's name, learned terms, and manual vocabulary. Capped to Whisper's budget.
    func sttPrompt(context: String) -> String? {
        var parts: [String] = []

        let ctx = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty { parts.append(String(ctx.suffix(400))) }

        var terms: [String] = []
        let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { terms.append(name) }
        terms.append(contentsOf: learnedTerms)
        terms.append(contentsOf: customVocabulary
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) })

        // De-dupe case-insensitively, preserve order.
        var seen = Set<String>()
        let uniq = terms.filter { t in
            let k = t.lowercased()
            guard !t.isEmpty, !seen.contains(k) else { return false }
            seen.insert(k); return true
        }
        if !uniq.isEmpty {
            parts.append(String(("Glossary: " + uniq.joined(separator: ", ") + ".").prefix(500)))
        }

        let result = parts.joined(separator: "\n")
        return result.isEmpty ? nil : result
    }

    // NOTE: stored in UserDefaults (plain text in ~/Library/Preferences/network.playai.vani.plist),
    // not the Keychain — by user preference, to avoid Keychain unlock prompts.
    func apiKey(for account: String) -> String {
        defaults.string(forKey: "apikey.\(account)") ?? ""
    }

    func setAPIKey(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: "apikey.\(account)")
        } else {
            defaults.set(trimmed, forKey: "apikey.\(account)")
        }
    }

    /// Build the configured STT provider, or throw if its key is missing.
    /// `context` is the text before the caret, used to prime transcription.
    func makeSTTProvider(context: String = "") throws -> STTProvider {
        let prompt = sttPrompt(context: context)
        switch sttChoice {
        case .openAI:
            let key = apiKey(for: KeyAccount.openAI)
            guard !key.isEmpty else { throw FlowError.missingAPIKey(provider: "OpenAI") }
            return OpenAISTTProvider(config: .openAISTT(apiKey: key), language: sttLanguage, prompt: prompt)
        case .openRouter:
            let key = apiKey(for: KeyAccount.openRouter)
            guard !key.isEmpty else { throw FlowError.missingAPIKey(provider: "OpenRouter") }
            return OpenRouterSTTProvider(apiKey: key, model: openRouterSTTModel, language: sttLanguage, prompt: prompt)
        case .groq:
            let key = apiKey(for: KeyAccount.groq)
            guard !key.isEmpty else { throw FlowError.missingAPIKey(provider: "Groq") }
            return OpenAISTTProvider(config: .groqSTT(apiKey: key), language: sttLanguage, prompt: prompt)
        case .parakeet:
            return FluidParakeetSTTProvider()
        case .localWhisper:
            guard !whisperModelPath.isEmpty else {
                throw FlowError.localTool("Set the whisper.cpp model path in Settings (e.g. ~/.vani/ggml-base.en.bin).")
            }
            return LocalWhisperProvider(binaryPath: whisperBinaryPath, modelPath: whisperModelPath)
        }
    }

    /// Build the configured LLM provider, or throw if its key is missing.
    /// `screenContext` (active-window content) is injected into the system prompt.
    func makeLLMProvider(screenContext: String = "") throws -> LLMProvider {
        let instruction = resolvedStyleInstruction
        switch llmChoice {
        case .openAI:
            let key = apiKey(for: KeyAccount.openAI)
            guard !key.isEmpty else { throw FlowError.missingAPIKey(provider: "OpenAI") }
            return OpenAILLMProvider(config: .openAILLM(apiKey: key), styleInstruction: instruction, screenContext: screenContext)
        case .openRouter:
            let key = apiKey(for: KeyAccount.openRouter)
            guard !key.isEmpty else { throw FlowError.missingAPIKey(provider: "OpenRouter") }
            return OpenAILLMProvider(config: .openRouterLLM(apiKey: key, model: openRouterModel), styleInstruction: instruction, screenContext: screenContext)
        case .groq:
            let key = apiKey(for: KeyAccount.groq)
            guard !key.isEmpty else { throw FlowError.missingAPIKey(provider: "Groq") }
            return OpenAILLMProvider(config: .init(
                apiKey: key,
                baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                model: "llama-3.3-70b-versatile"), styleInstruction: instruction, screenContext: screenContext)
        case .anthropic:
            let key = apiKey(for: KeyAccount.anthropic)
            guard !key.isEmpty else { throw FlowError.missingAPIKey(provider: "Anthropic") }
            return AnthropicLLMProvider(apiKey: key, styleInstruction: instruction, screenContext: screenContext)
        case .ollama:
            return OpenAILLMProvider(config: .ollama(model: "llama3.1:8b"), styleInstruction: instruction, screenContext: screenContext)
        }
    }
}
