import Foundation

/// Speech-to-text via the OpenAI-compatible `/audio/transcriptions` endpoint.
/// Works with OpenAI (`whisper-1`) and Groq (`whisper-large-v3-turbo`).
public struct OpenAISTTProvider: STTProvider {
    private let config: OpenAICompatibleConfig
    private let language: String?
    private let prompt: String?
    private let transport: HTTPTransport

    /// - language: ISO-639-1 code (e.g. "en") to skip auto-detection; nil = auto.
    /// - prompt: priming text biasing transcription toward names/jargon/punctuation.
    public init(config: OpenAICompatibleConfig,
                language: String? = nil,
                prompt: String? = nil,
                transport: HTTPTransport = URLSession.shared) {
        self.config = config
        self.language = language
        self.prompt = prompt
        self.transport = transport
    }

    public func transcribe(audioFileURL: URL) async throws -> String {
        guard !config.apiKey.isEmpty else { throw FlowError.missingAPIKey(provider: "OpenAI STT") }

        let url = config.baseURL.appendingPathComponent("audio/transcriptions")
        let boundary = "Vani-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45   // audio upload may be larger; still bounded
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioFileURL)
        } catch {
            throw FlowError.network("Could not read audio file: \(error.localizedDescription)")
        }

        request.httpBody = Self.multipartBody(
            boundary: boundary,
            model: config.model,
            filename: audioFileURL.lastPathComponent,
            audio: audioData,
            language: language,
            prompt: prompt
        )

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

    static func multipartBody(boundary: String, model: String, filename: String, audio: Data,
                              language: String? = nil, prompt: String? = nil) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        field("model", model)
        field("response_format", "json")
        if let language, !language.isEmpty { field("language", language) }
        if let prompt, !prompt.isEmpty { field("prompt", prompt) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(audio)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }
}
