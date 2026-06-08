import AppKit
import Combine
import SwiftUI
import NaturalLanguage
import FlowCore

/// Central coordinator: owns the recorder + hotkey, runs the unified dictation/command
/// pipeline, drives the HUD, and publishes status to the menu.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Mode { case dictation, command }

    enum Status: Equatable {
        case idle, recording, transcribing, thinking, error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastInserted: String = ""
    @Published private(set) var hotkeyInstalled: Bool = false

    // Onboarding "try it" state — runs the pipeline but shows the result in-app
    // instead of pasting into another app.
    @Published private(set) var testRecording: Bool = false
    @Published private(set) var testResult: String = ""
    @Published private(set) var testError: String = ""
    @Published private(set) var detectedLanguage: String = ""
    @Published private(set) var parakeetStatus: String = ""

    private let recorder = AudioRecorder()
    private let hotkey = HotkeyManager()
    private var processingTask: Task<Void, Never>?

    private var capturedSelection: String = ""
    private var capturedContext: String = ""
    private var screenContextTask: Task<ScreenContextService.Capture, Never>?
    private var currentMode: Mode = .dictation

    private var gestureDictation: GestureController!
    private var gestureCommand: GestureController!

    private init() {
        gestureDictation = GestureController(
            startCapture: { [weak self] in self?.startCapture(mode: .dictation) ?? false },
            confirmHUD: { [weak self] in self?.confirmRecordingHUD() },
            stopAndProcess: { [weak self] in self?.endRecordingAndProcess() },
            discard: { [weak self] in self?.discardCapture() })
        gestureCommand = GestureController(
            startCapture: { [weak self] in self?.startCapture(mode: .command) ?? false },
            confirmHUD: { [weak self] in self?.confirmRecordingHUD() },
            stopAndProcess: { [weak self] in self?.endRecordingAndProcess() },
            discard: { [weak self] in self?.discardCapture() })
    }

    /// Request permissions, bind the hotkey, install the tap. Call once at launch.
    func bootstrap() async {
        _ = await AudioRecorder.requestPermission()
        if !HotkeyManager.hasAccessibility {
            HotkeyManager.promptForAccessibility()
        }
        reloadHotkeys()
        FocusWatcher.shared.start()
        installEscapeToCancel()
    }

    /// Esc cancels an in-flight recording/processing, from any app (passive monitor —
    /// it never swallows the key, so Esc still works normally everywhere).
    private func installEscapeToCancel() {
        let handle: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 53 else { return }   // 53 = Escape
            Task { @MainActor in self?.cancelProcessing() }
        }
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { handle($0) }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { handle($0); return $0 }
    }

    /// (Re)bind the configured hotkeys and ensure the tap is running.
    func reloadHotkeys() {
        let s = SettingsStore.shared
        hotkey.clearRegistrations()
        hotkey.register(s.dictationHotkey, customFlags: s.customDictationFlags,
                        onPress: { [weak self] in self?.gestureDictation.onPress() },
                        onRelease: { [weak self] in self?.gestureDictation.onRelease() })
        if s.commandHotkey != .off, s.commandHotkey != s.dictationHotkey {
            hotkey.register(s.commandHotkey, customFlags: s.customCommandFlags,
                            onPress: { [weak self] in self?.gestureCommand.onPress() },
                            onRelease: { [weak self] in self?.gestureCommand.onRelease() })
        }
        hotkeyInstalled = hotkey.start()
    }

    var accessibilityGranted: Bool { HotkeyManager.hasAccessibility }

    /// Download + load the Parakeet model now so offline transcription is ready.
    func prepareParakeet() {
        parakeetStatus = "Downloading model… (~600 MB, one time)"
        Task { [weak self] in
            do {
                try await ParakeetEngine.shared.preload()
                self?.parakeetStatus = "Ready — works offline"
            } catch {
                self?.parakeetStatus = "Failed: \(error.localizedDescription)"
            }
        }
    }

    func openAccessibilitySettings() {
        HotkeyManager.promptForAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Recording

    /// Start recording silently (no HUD/sound). Returns false if it can't start.
    /// Audio captures from this instant so the first word isn't clipped.
    @discardableResult
    private func startCapture(mode: Mode) -> Bool {
        guard status == .idle || isError(status) else { return false }
        guard AudioRecorder.hasPermission else { fail("Microphone permission not granted"); return false }

        currentMode = mode
        applyPowerMode()
        // Snapshot the selection ONLY for Command Mode (it's what the command edits).
        // Dictation never uses the selection, so we skip it there — that avoids the ⌘C
        // clipboard fallback firing (and clobbering the clipboard) on every dictation.
        capturedSelection = (mode == .command) ? SelectionAccess.readForRouting() : ""
        capturedContext = SelectionAccess.contextBeforeCursor()

        // Capture the active-window context now so it overlaps with speaking + STT and
        // is ready by the time the cleanup LLM runs. Skipped if disabled.
        let store = SettingsStore.shared
        if store.screenContextEnabled {
            let useOCR = store.screenOCREnabled
            screenContextTask = Task.detached { await ScreenContextService.capture(useOCR: useOCR) }
        } else {
            screenContextTask = nil
        }

        guard recorder.start() else { fail("Couldn't start the microphone"); return false }
        status = .recording
        return true
    }

    /// Reveal the recording HUD + play the start cue (once a gesture is confirmed).
    private func confirmRecordingHUD() {
        SoundCue.start()
        switch currentMode {
        case .dictation:
            HUDController.shared.show(phase: .listening(command: false), title: "Listening")
        case .command:
            let title = capturedSelection.isEmpty ? "Ask anything" : "Command on selection"
            HUDController.shared.show(phase: .listening(command: true), title: title)
        }
    }

    /// Drop an in-progress capture without processing (a quick tap).
    private func discardCapture() {
        if let url = recorder.stop() { try? FileManager.default.removeItem(at: url) }
        status = .idle
        HUDController.shared.hide()
    }

    /// Begin recording with HUD immediately (used by the menu "Test Dictation").
    func beginRecording(mode: Mode) {
        guard startCapture(mode: mode) else { return }
        confirmRecordingHUD()
    }

    /// Toggle used by the menu "Test Dictation" button.
    func toggleDictation() {
        if status == .recording { endRecordingAndProcess() } else { beginRecording(mode: .dictation) }
    }

    var isRecording: Bool { status == .recording }

    func endRecordingAndProcess() {
        guard status == .recording, let url = recorder.stop() else { return }
        status = .transcribing
        let mode = currentMode
        processingTask = Task { [weak self] in
            await self?.process(url: url, mode: mode)
        }
    }

    // MARK: - Unified pipeline

    private func process(url: URL, mode: Mode) async {
        defer { try? FileManager.default.removeItem(at: url) }
        let selection = capturedSelection
        let context = capturedContext

        // Local diagnostics (see menu → Diagnostics). Filled in as we go; recorded on exit.
        let started = Date()
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        var diagTranscript = "", diagContext = "", diagOutput = "", diagSource = "—"
        var diagLeak = false
        defer {
            Diagnostics.shared.record(app: frontApp, mode: "\(mode)", transcript: diagTranscript,
                                      context: diagContext, contextSource: diagSource, output: diagOutput,
                                      leakStripped: diagLeak, ms: Int(Date().timeIntervalSince(started) * 1000))
        }

        do {
            let stt = try SettingsStore.shared.makeSTTProvider(context: context)

            status = .transcribing
            HUDController.shared.show(phase: .transcribing, title: "Transcribing")
            let transcript = try await stt.transcribe(audioFileURL: url)
            diagTranscript = transcript

            status = .thinking
            // Active-window context captured at recording start (ready by now).
            let capture = await screenContextTask?.value
            let screenContext = capture?.text ?? ""
            diagContext = screenContext
            diagSource = capture?.source ?? (SettingsStore.shared.screenContextEnabled ? "—" : "disabled")

            switch mode {
            case .dictation:
                HUDController.shared.show(phase: .cleaning, title: "Cleaning up",
                                          detail: SettingsStore.shared.cleanupModelDisplay)
                // Clean up with the LLM; if it's unavailable (offline / no key / error),
                // fall back to the raw transcript so dictation still works offline.
                var cleaned = transcript
                var fellBack = false
                do {
                    let llm = try SettingsStore.shared.makeLLMProvider(screenContext: screenContext)
                    var out = try await llm.process(transcript: transcript, selection: "")
                    if !screenContext.isEmpty {
                        let safe = stripContextLeak(out, transcript: transcript, context: screenContext)
                        if safe != out { diagLeak = true }
                        // If the model echoed the screen context, redo without it.
                        if safe.isEmpty {
                            let plain = try SettingsStore.shared.makeLLMProvider()
                            out = try await plain.process(transcript: transcript, selection: "")
                        } else {
                            out = safe
                        }
                    }
                    if !out.isEmpty { cleaned = out }
                } catch {
                    fellBack = true
                }
                let final = applySnippets(cleaned)
                diagOutput = final
                TextInserter.insert(final)
                if fellBack {
                    lastInserted = final
                    SettingsStore.shared.addHistory(final)
                    status = .idle
                    SoundCue.done()
                    HUDController.shared.show(phase: .inserted, title: "Inserted", detail: "raw · offline", autoHide: 1.4)
                } else {
                    succeed(with: final)
                }

            case .command where !selection.isEmpty:
                // Command needs the LLM (no offline fallback for edits).
                let llm = try SettingsStore.shared.makeLLMProvider(screenContext: screenContext)
                HUDController.shared.show(phase: .cleaning, title: "Editing selection",
                                          detail: SettingsStore.shared.cleanupModelDisplay)
                // No leak-stripping here: a command rewrite legitimately reuses the
                // selection (which is on screen), so stripping screen-matching lines
                // would corrupt the result. Leak-stripping stays a dictation-only guard.
                let text = try await llm.rewrite(instruction: transcript, selection: selection)
                let final = applySnippets(text.isEmpty ? selection : text)
                diagOutput = final
                TextInserter.insert(final)
                succeed(with: final)

            case .command:
                // No selection → answer the question (needs the LLM), show in popover.
                let llm = try SettingsStore.shared.makeLLMProvider()
                HUDController.shared.show(phase: .cleaning, title: "Thinking")
                // Answer mode passes context inline; combine caret text + screen content.
                let answerContext = [context, screenContext].filter { !$0.isEmpty }.joined(separator: "\n\n")
                let reply = try await llm.answer(question: transcript, context: answerContext)
                diagOutput = reply
                HUDController.shared.hide()
                status = .idle
                SoundCue.done()
                lastInserted = reply
                AnswerHUDController.shared.show(reply.isEmpty ? "(no answer)" : reply)
            }
        } catch {
            if Task.isCancelled { return }   // user pressed Esc — cancelProcessing cleaned up
            fail((error as? FlowError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Abort an in-flight recording/processing (Esc). Cancels the network call and resets.
    func cancelProcessing() {
        guard status != .idle else { return }
        processingTask?.cancel()
        processingTask = nil
        screenContextTask?.cancel()
        if status == .recording { _ = recorder.stop() }
        status = .idle
        HUDController.shared.hide()
    }

    // MARK: - Onboarding test (no paste; result shown in the wizard)

    func toggleTest() {
        if testRecording { stopTest() } else { startTest() }
    }

    private func startTest() {
        guard status == .idle || isError(status) else { return }
        guard AudioRecorder.hasPermission else { testError = "Microphone permission not granted"; return }
        guard recorder.start() else { testError = "Couldn't start the microphone"; return }
        testError = ""
        testResult = ""
        testRecording = true
        SoundCue.start()
    }

    private func stopTest() {
        guard testRecording, let url = recorder.stop() else { return }
        testRecording = false
        SoundCue.done()
        Task { [weak self] in await self?.runTest(url: url) }
    }

    private func runTest(url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let stt = try SettingsStore.shared.makeSTTProvider()
            let llm = try SettingsStore.shared.makeLLMProvider()
            let transcript = try await stt.transcribe(audioFileURL: url)
            detectAndSetLanguage(from: transcript)
            let text = try await llm.process(transcript: transcript, selection: "")
            testResult = text.isEmpty ? transcript : text
        } catch {
            testError = (error as? FlowError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// On-device language detection (NaturalLanguage) — sets the transcription
    /// language automatically from the test sample, no API call.
    private func detectAndSetLanguage(from text: String) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let code = recognizer.dominantLanguage?.rawValue {
            detectedLanguage = code
            SettingsStore.shared.language = code
        }
    }

    // MARK: - Learned corrections

    func teachWord() {
        guard let entry = QuickPrompt.text(
            title: "Teach a word",
            message: "Add a name or term so transcription spells it correctly. Separate multiple with commas.",
            prefill: "") else { return }
        addLearned(from: entry)
    }

    func correctLast() {
        guard !lastInserted.isEmpty else { teachWord(); return }
        guard let corrected = QuickPrompt.text(
            title: "Correct last result",
            message: "Fix the text below — any new names get learned for next time.",
            prefill: lastInserted) else { return }
        // Learn the proper-noun-ish words from the corrected version.
        addLearned(Self.capitalizedTerms(in: corrected))
    }

    private func addLearned(from raw: String) {
        let terms = raw.split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        addLearned(terms)
    }

    private func addLearned(_ terms: [String]) {
        var list = SettingsStore.shared.learnedTerms
        for t in terms where !t.isEmpty
            && !list.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
            list.append(t)
        }
        SettingsStore.shared.learnedTerms = list
    }

    private static func capitalizedTerms(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters) }
            .filter { $0.count > 1 && ($0.first?.isUppercase ?? false) }
    }

    // MARK: - Outcomes

    private func succeed(with text: String) {
        lastInserted = text
        SettingsStore.shared.addHistory(text)
        status = .idle
        SoundCue.done()
        let words = text.split { $0 == " " || $0.isNewline }.count
        HUDController.shared.show(phase: .inserted, title: "Inserted",
                                  detail: "\(words) word\(words == 1 ? "" : "s")", autoHide: 1.0)
    }

    private func fail(_ message: String) {
        status = .error(message)
        SoundCue.error()
        HUDController.shared.show(phase: .error, title: "Something went wrong", detail: message, autoHide: 3.5)
    }

    /// Power Mode: if the frontmost app has a profile, override mode + language for this dictation.
    private func applyPowerMode() {
        let store = SettingsStore.shared
        guard store.powerModeEnabled,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              let profile = store.powerProfile(forBundleID: bundleID) else {
            store.overrideModeID = nil
            store.overrideLanguage = nil
            return
        }
        store.overrideModeID = profile.modeID
        store.overrideLanguage = profile.language.isEmpty ? nil : profile.language
    }

    private func applySnippets(_ text: String) -> String {
        TextTransforms.applyReplacements(text, SettingsStore.shared.snippetPairs())
    }

    /// Safety net: occasionally the cleanup model copies a line out of the screen
    /// context instead of just using it. Drop any output line that came verbatim from
    /// the context but not from what the user actually said. Returns the cleaned text,
    /// or "" if everything was a leak (caller then falls back to a context-free pass).
    private func stripContextLeak(_ output: String, transcript: String, context: String) -> String {
        let ctx = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ctx.isEmpty else { return output }
        func norm(_ s: String) -> String {
            s.lowercased().components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        let ctxN = norm(ctx)
        let trN = norm(transcript)
        let kept = output.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.count >= 20 else { return true }            // short lines are safe
            let ln = norm(String(l))
            return !(ctxN.contains(ln) && !trN.contains(ln))    // drop screen-sourced lines
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isError(_ s: Status) -> Bool {
        if case .error = s { return true }
        return false
    }

    // MARK: - UI helpers

    var menuIcon: String {
        switch status {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing, .thinking: return "waveform"
        case .error: return "exclamationmark.triangle"
        }
    }

    /// The Vani logo mark for the menu bar. Template (system-tinted) when idle so it
    /// adapts to light/dark menu bars; tinted Iris while active; orange on error.
    var menuBarImage: NSImage {
        switch status {
        case .idle:
            return VaniGlyph.image(color: .labelColor, template: true)
        case .recording, .transcribing, .thinking:
            return VaniGlyph.image(color: NSColor(hex: SettingsStore.shared.accentHex), template: false)
        case .error:
            return VaniGlyph.image(color: NSColor(hex: 0xE0734A), template: false)
        }
    }

    var statusText: String {
        let key = SettingsStore.shared.dictationHotkey.label
        switch status {
        case .idle: return "Ready — hold \(key) to dictate or command"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .thinking: return "Working…"
        case .error(let m): return "Error: \(m)"
        }
    }
}
