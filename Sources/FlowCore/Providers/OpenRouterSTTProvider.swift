import Foundation

/// Speech-to-text via OpenRouter's `/audio/transcriptions` endpoint.
///
/// Unlike OpenAI/Groq (multipart form upload), OpenRouter takes a JSON body with
/// **base64-encoded** audio: `{"model", "input_audio": {"data", "format"}}`.
/// Lets a single OpenRouter key drive both transcription and cleanup.
public struct OpenRouterSTTProvider: STTProvider {
    private let apiKey: String
    private let model: String
    private let language: String?
    private let prompt: String?
    private let baseURL: URL
    private let transport: HTTPTransport

    public init(
        apiKey: String,
        model: String = "openai/gpt-4o-mini-transcribe",
        language: String? = nil,
        prompt: String? = nil,
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.language = language
        self.prompt = prompt
        self.baseURL = baseURL
        self.transport = transport
    }

    public func transcribe(audioFileURL: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw FlowError.missingAPIKey(provider: "OpenRouter STT") }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioFileURL)
        } catch {
            throw FlowError.network("Could not read audio file: \(error.localizedDescription)")
        }

        // OpenRouter accepts wav, mp3, flac, m4a, ogg, webm, aac — derive from the file extension.
        let ext = audioFileURL.pathExtension.lowercased()
        let format = ext.isEmpty ? "wav" : ext

        let url = baseURL.appendingPathComponent("audio/transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": model,
            "input_audio": [
                "data": audioData.base64EncodedString(),
                "format": format,
            ],
        ]
        if let language, !language.isEmpty { payload["language"] = language }
        if let prompt, !prompt.isEmpty { payload["prompt"] = prompt }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, http) = try await transport.send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw FlowError.invalidResponse(statusCode: http.statusCode,
                                            body: String(decoding: data, as: UTF8.self))
        }

        struct TranscriptionResponse: Decodable { let text: String }
        do {
            let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw FlowError.emptyTranscript }
            return trimmed
        } catch let error as FlowError {
            throw error
        } catch {
            throw FlowError.decodingFailed(error.localizedDescription)
        }
    }
}
