import Foundation

/// Text cleanup via the Anthropic Messages API.
///
/// Default model is `claude-haiku-4-5` — the fastest/cheapest Claude, well suited
/// to the low-latency dictation cleanup task. `thinking` is intentionally omitted
/// (latency-sensitive). Use `claude-sonnet-4-6` for higher-quality rewrites.
public struct AnthropicLLMProvider: LLMProvider {
    private let apiKey: String
    private let model: String
    private let styleInstruction: String
    private let screenContext: String
    private let baseURL: URL
    private let transport: HTTPTransport

    public init(
        apiKey: String,
        model: String = "claude-haiku-4-5",
        styleInstruction: String = "",
        screenContext: String = "",
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.styleInstruction = styleInstruction
        self.screenContext = screenContext
        self.baseURL = baseURL
        self.transport = transport
    }

    private var contextBlock: String { FlowPrompt.screenContextBlock(screenContext) }

    public func cleanup(_ rawTranscript: String) async throws -> String {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return try await chat(system: FlowPrompt.cleanupSystem(instruction: styleInstruction) + contextBlock,
                              user: FlowPrompt.cleanupUser(trimmed))
    }

    public func rewrite(instruction: String, selection: String) async throws -> String {
        let user = FlowPrompt.commandUser(instruction: instruction, selection: selection)
        return try await chat(system: FlowPrompt.systemCommand + contextBlock, user: user)
    }

    public func process(transcript: String, selection: String) async throws -> String {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let sel = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        if sel.isEmpty {
            return try await chat(system: FlowPrompt.cleanupSystem(instruction: styleInstruction) + contextBlock,
                                  user: FlowPrompt.cleanupUser(t))
        }
        return try await chat(system: FlowPrompt.unifiedSystem(instruction: styleInstruction) + contextBlock,
                              user: FlowPrompt.unifiedUser(transcript: t, selection: sel))
    }

    public func answer(question: String, context: String) async throws -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return "" }
        return try await chat(system: FlowPrompt.systemAnswer,
                              user: FlowPrompt.answerUser(question: q, context: context))
    }

    private func chat(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw FlowError.missingAPIKey(provider: "Anthropic") }

        let url = baseURL.appendingPathComponent("messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30   // don't hang the HUD on a stalled connection
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": system,
            "messages": [
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, http) = try await transport.send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw FlowError.invalidResponse(statusCode: http.statusCode,
                                            body: String(decoding: data, as: UTF8.self))
        }

        struct MessagesResponse: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        do {
            let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
            let text = decoded.content
                .filter { $0.type == "text" }
                .compactMap { $0.text }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text
        } catch {
            throw FlowError.decodingFailed(error.localizedDescription)
        }
    }
}
