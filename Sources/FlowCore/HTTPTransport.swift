import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Seam over `URLSession` so providers can be unit-tested without real network calls.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await self.data(for: request)
        } catch {
            throw FlowError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw FlowError.network("Non-HTTP response")
        }
        return (responseData, http)
    }
}
