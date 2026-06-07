import Foundation
import FluidAudio
import FlowCore

/// Loads the Parakeet ASR models once and reuses them across dictations.
/// Models auto-download from Hugging Face on first use, then run on the Neural Engine.
actor ParakeetEngine {
    static let shared = ParakeetEngine()
    private var manager: AsrManager?

    func transcribe(fileURL: URL) async throws -> String {
        let asr = try await ensureLoaded()
        // Fresh decoder state per dictation (state is for streaming continuity).
        var decoderState = try TdtDecoderState()
        let result = try await asr.transcribe(fileURL, decoderState: &decoderState)
        return result.text
    }

    /// Force model download + load ahead of time (so it works offline later).
    func preload() async throws { _ = try await ensureLoaded() }

    private func ensureLoaded() async throws -> AsrManager {
        if let manager { return manager }
        let models = try await AsrModels.downloadAndLoad()
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        manager = asr
        return asr
    }
}

/// Fully offline, on-device speech-to-text via Parakeet (FluidAudio / Core ML on the ANE).
/// No API key. First use downloads the model (~600 MB); afterwards it's local + fast.
/// Note: Parakeet doesn't take a vocabulary/prompt, so custom-vocabulary priming is
/// not applied for this engine (it's still very accurate and multilingual).
struct FluidParakeetSTTProvider: STTProvider {
    func transcribe(audioFileURL: URL) async throws -> String {
        do {
            let text = try await ParakeetEngine.shared.transcribe(fileURL: audioFileURL)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw FlowError.emptyTranscript }
            return trimmed
        } catch let error as FlowError {
            throw error
        } catch {
            throw FlowError.localTool("Parakeet failed: \(error.localizedDescription)")
        }
    }
}
