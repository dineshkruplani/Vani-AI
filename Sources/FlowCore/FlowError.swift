import Foundation

/// Errors surfaced by the FlowCore pipeline and providers.
public enum FlowError: Error, LocalizedError, Equatable {
    case missingAPIKey(provider: String)
    case invalidResponse(statusCode: Int, body: String)
    case decodingFailed(String)
    case emptyTranscript
    case network(String)
    case localTool(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No API key configured for \(provider). Add one in Settings."
        case .invalidResponse(let code, let body):
            let snippet = body.count > 300 ? String(body.prefix(300)) + "…" : body
            return "Provider returned HTTP \(code): \(snippet)"
        case .decodingFailed(let detail):
            return "Could not parse the provider response: \(detail)"
        case .emptyTranscript:
            return "Nothing was transcribed — the recording may have been silent."
        case .network(let detail):
            return "Network error: \(detail)"
        case .localTool(let detail):
            return detail
        }
    }
}
