import Foundation

/// Orchestrates the core dictation pipeline: recorded audio → transcript → cleaned text.
///
/// UI-free and provider-agnostic so it can be unit-tested and reused across
/// hotkey-driven and button-driven entry points.
public struct DictationPipeline: Sendable {
    private let stt: STTProvider
    private let llm: LLMProvider

    public init(stt: STTProvider, llm: LLMProvider) {
        self.stt = stt
        self.llm = llm
    }

    /// Stages reported back to the UI as the pipeline runs.
    public enum Stage: Sendable, Equatable {
        case transcribing
        case cleaning
    }

    /// Run transcription then cleanup. `onStage` lets the caller update UI state.
    public func process(
        audioFileURL: URL,
        onStage: (@Sendable (Stage) -> Void)? = nil
    ) async throws -> String {
        onStage?(.transcribing)
        let transcript = try await stt.transcribe(audioFileURL: audioFileURL)

        onStage?(.cleaning)
        let cleaned = try await llm.cleanup(transcript)

        // If cleanup returns nothing usable, fall back to the raw transcript
        // rather than inserting an empty string.
        return cleaned.isEmpty ? transcript : cleaned
    }
}
