import Foundation

/// Text cleanup via the OpenAI-compatible `/chat/completions` endpoint.
/// Works with OpenAI (`gpt-4o-mini`), Groq, and a local Ollama server.
public struct OpenAILLMProvider: LLMProvider {
    private let config: OpenAICompatibleConfig
    private let styleInstruction: String
    private let screenContext: String
    private let transport: HTTPTransport

    public init(config: OpenAICompatibleConfig,
                styleInstruction: String = "",
                screenContext: String = "",
                transport: HTTPTransport = URLSession.shared) {
        self.config = config
        self.styleInstruction = styleInstruction
        self.screenContext = screenContext
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
        guard !config.apiKey.isEmpty else { throw FlowError.missingAPIKey(provider: "OpenAI LLM") }

        let url = config.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30   // don't hang the HUD on a stalled connection
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": config.model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, http) = try await transport.send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw FlowError.invalidResponse(statusCode: http.statusCode,
                                            body: String(decoding: data, as: UTF8.self))
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw FlowError.decodingFailed("No choices returned")
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as FlowError {
            throw error
        } catch {
            throw FlowError.decodingFailed(error.localizedDescription)
        }
    }
}
