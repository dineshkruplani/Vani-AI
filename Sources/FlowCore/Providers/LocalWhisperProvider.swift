import Foundation

/// Fully offline speech-to-text using a local `whisper.cpp` binary (`whisper-cli`).
///
/// Requires the user to install whisper.cpp and a GGML model, e.g.:
///   brew install whisper-cpp
///   curl -L -o ~/.vani/ggml-base.en.bin \
///     https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
///
/// Pipeline: input audio → 16 kHz mono WAV (via macOS `afconvert`) → `whisper-cli` → text.
/// No network, no API key, zero marginal cost.
public struct LocalWhisperProvider: STTProvider {
    private let binaryPath: String
    private let modelPath: String
    private let afconvertPath: String

    public init(
        binaryPath: String,
        modelPath: String,
        afconvertPath: String = "/usr/bin/afconvert"
    ) {
        self.binaryPath = binaryPath
        self.modelPath = modelPath
        self.afconvertPath = afconvertPath
    }

    public func transcribe(audioFileURL: URL) async throws -> String {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: binaryPath) else {
            throw FlowError.localTool("whisper-cli not found at \(binaryPath). Install it (brew install whisper-cpp) and set the path in Settings.")
        }
        guard fm.fileExists(atPath: modelPath) else {
            throw FlowError.localTool("Whisper model not found at \(modelPath). Download a ggml model and set its path in Settings.")
        }

        // Run the whole blocking pipeline off the cooperative thread pool.
        return try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                do {
                    let text = try Self.runPipeline(
                        audioFileURL: audioFileURL,
                        binaryPath: binaryPath,
                        modelPath: modelPath,
                        afconvertPath: afconvertPath
                    )
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runPipeline(
        audioFileURL: URL,
        binaryPath: String,
        modelPath: String,
        afconvertPath: String
    ) throws -> String {
        let tmp = FileManager.default.temporaryDirectory
        let wavURL = tmp.appendingPathComponent("vani-\(UUID().uuidString).wav")
        let outPrefix = tmp.appendingPathComponent("vani-\(UUID().uuidString)")
        let txtURL = outPrefix.appendingPathExtension("txt")
        defer {
            try? FileManager.default.removeItem(at: wavURL)
            try? FileManager.default.removeItem(at: txtURL)
        }

        // 1. Convert to 16 kHz mono signed-16 little-endian WAV (what whisper.cpp expects).
        try run(afconvertPath, [
            "-f", "WAVE", "-d", "LEI16@16000", "-c", "1",
            audioFileURL.path, wavURL.path,
        ])

        // 2. Transcribe. -nt no timestamps, -otxt write <prefix>.txt, -np quiet.
        try run(binaryPath, [
            "-m", modelPath,
            "-f", wavURL.path,
            "-nt", "-np",
            "-otxt", "-of", outPrefix.path,
        ])

        // 3. Read the transcript.
        guard let text = try? String(contentsOf: txtURL, encoding: .utf8) else {
            throw FlowError.localTool("whisper-cli produced no transcript output.")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FlowError.emptyTranscript }
        return trimmed
    }

    /// Run a subprocess, throwing `.localTool` with stderr on non-zero exit.
    private static func run(_ launchPath: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw FlowError.localTool("Couldn't launch \(launchPath): \(error.localizedDescription)")
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let msg = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw FlowError.localTool("\((launchPath as NSString).lastPathComponent) failed (exit \(process.terminationStatus)): \(msg.isEmpty ? "no output" : msg)")
        }
    }
}
