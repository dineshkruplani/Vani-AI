import Foundation

/// Converts recorded audio into a raw transcript.
public protocol STTProvider: Sendable {
    /// Transcribe the audio at `audioFileURL` (e.g. an .m4a or .wav file).
    func transcribe(audioFileURL: URL) async throws -> String
}

/// Cleans up / rewrites text (the dictation post-processing step).
public protocol LLMProvider: Sendable {
    /// Turn a raw transcript into polished written text.
    func cleanup(_ rawTranscript: String) async throws -> String

    /// Command Mode: apply a spoken `instruction` to the `selection` and return the replacement.
    func rewrite(instruction: String, selection: String) async throws -> String

    /// Unified entry point: given a `transcript` and the current `selection` (may be empty),
    /// the model decides whether it's an edit command or dictation, and returns the text to insert.
    func process(transcript: String, selection: String) async throws -> String

    /// Ask/answer mode (Command key with nothing selected): answer the spoken question.
    func answer(question: String, context: String) async throws -> String
}

/// Connection config shared by all OpenAI-compatible endpoints
/// (OpenAI itself, Groq, and a local Ollama/llama.cpp server).
public struct OpenAICompatibleConfig: Sendable {
    public var apiKey: String
    public var baseURL: URL
    public var model: String

    public init(apiKey: String, baseURL: URL, model: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    // MARK: - Presets

    public static func openAISTT(apiKey: String, model: String = "whisper-1") -> Self {
        .init(apiKey: apiKey, baseURL: URL(string: "https://api.openai.com/v1")!, model: model)
    }

    public static func openAILLM(apiKey: String, model: String = "gpt-4o-mini") -> Self {
        .init(apiKey: apiKey, baseURL: URL(string: "https://api.openai.com/v1")!, model: model)
    }

    public static func groqSTT(apiKey: String, model: String = "whisper-large-v3-turbo") -> Self {
        .init(apiKey: apiKey, baseURL: URL(string: "https://api.groq.com/openai/v1")!, model: model)
    }

    /// OpenRouter LLM gateway (chat only — no audio transcription).
    /// Model names are namespaced, e.g. "openai/gpt-4o-mini", "anthropic/claude-3.5-haiku".
    public static func openRouterLLM(apiKey: String, model: String = "openai/gpt-4o-mini") -> Self {
        .init(apiKey: apiKey, baseURL: URL(string: "https://openrouter.ai/api/v1")!, model: model)
    }

    /// Local Ollama exposing the OpenAI-compatible API (key is ignored by Ollama).
    public static func ollama(model: String, baseURL: URL = URL(string: "http://localhost:11434/v1")!) -> Self {
        .init(apiKey: "ollama", baseURL: baseURL, model: model)
    }
}
