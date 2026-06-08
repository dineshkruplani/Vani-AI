import Foundation

/// Structured screen understanding extracted from a screenshot by a vision model.
/// All fields optional so a partial/short model response still decodes.
public struct ScreenInsight: Codable, Sendable {
    public var summary: String?
    public var replyingTo: String?
    public var focusedField: String?
    public var names: [String]?
    public var tone: String?
    public init(summary: String? = nil, replyingTo: String? = nil, focusedField: String? = nil,
                names: [String]? = nil, tone: String? = nil) {
        self.summary = summary; self.replyingTo = replyingTo; self.focusedField = focusedField
        self.names = names; self.tone = tone
    }

    /// True when the model returned nothing usable.
    public var isEmpty: Bool {
        (summary?.isEmpty ?? true) && (replyingTo?.isEmpty ?? true) &&
        (focusedField?.isEmpty ?? true) && (names?.isEmpty ?? true) && (tone?.isEmpty ?? true)
    }
}

/// Sends a screenshot to a vision-capable model (default: `openai/gpt-4o-mini` via
/// OpenRouter) and gets back distilled, structured context. Used by the two-stage
/// "vision distills → text model finalizes" flow: this runs while the user is
/// dictating, so its latency is hidden behind speech.
public struct VisionContextProvider: Sendable {
    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let transport: HTTPTransport

    public init(apiKey: String,
                model: String = "openai/gpt-4o-mini",
                baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
                transport: HTTPTransport = URLSession.shared) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.transport = transport
    }

    public func extract(imageJPEG: Data, appName: String, fieldHint: String = "") async throws -> ScreenInsight {
        guard !apiKey.isEmpty else { throw FlowError.missingAPIKey(provider: "OpenRouter (vision)") }

        let dataURL = "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"
        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fieldNote = fieldHint.isEmpty ? "" : " The focused window is: \(fieldHint)."
        let userText = "The user is dictating or editing text where their cursor is, in \(appName).\(fieldNote) Analyze the screenshot and return the JSON context."

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "max_tokens": 500,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.system],
                ["role": "user", "content": [
                    ["type": "text", "text": userText],
                    ["type": "image_url", "image_url": ["url": dataURL]],
                ]],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, http) = try await transport.send(request)
        guard (200..<300).contains(http.statusCode) else {
            throw FlowError.invalidResponse(statusCode: http.statusCode,
                                            body: String(decoding: data, as: UTF8.self))
        }

        struct Resp: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw FlowError.decodingFailed("Vision: no content")
        }
        // The model may wrap JSON in ```json fences despite response_format — strip them.
        let cleaned = content.contains("```")
            ? String(content.drop(while: { $0 != "{" }).prefix(while: { $0 != "`" }))
            : content
        let toParse = (cleaned.data(using: .utf8) ?? jsonData)
        return (try? JSONDecoder().decode(ScreenInsight.self, from: toParse)) ?? ScreenInsight()
    }

    static let system = """
    You analyze a screenshot of the user's screen to help a dictation app write or edit \
    text where the user's cursor is. Respond with ONLY a JSON object with these keys:
    - "summary": 1-2 sentences on what's on screen relevant to what the user is about to write or edit.
    - "replyingTo": if the user is replying to a message/email/comment, the gist of what they're \
    responding to; otherwise "".
    - "focusedField": what the text input under the cursor is for (e.g. "WhatsApp reply box", \
    "email body", "code comment"); otherwise "".
    - "names": array of proper nouns, people, products, or technical terms visible that should be \
    spelled correctly; otherwise [].
    - "tone": the appropriate writing tone for this context (e.g. "casual", "formal"); otherwise "".
    Output only the JSON object. Never invent content that isn't visible on screen.
    """
}
