// Tests/SwiftGeminiInteractionsTests/MockURLProtocol.swift
import Foundation
@testable import SwiftGeminiInteractions

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeTestClient(apiKey: String = "test-key", apiRevision: String = "2026-05-20") -> InteractionsClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return InteractionsClient(apiKey: apiKey, apiRevision: apiRevision, session: session)
}

func makeInteractionJSON(id: String = "v1_test", status: String = "completed", model: String = "gemini-3-flash-preview") -> Data {
    """
    {
        "id": "\(id)",
        "object": "interaction",
        "model": "\(model)",
        "status": "\(status)",
        "created": "2026-05-24T10:00:00Z",
        "steps": [
            {"type": "model_output", "content": [{"type": "text", "text": "Hello!"}]}
        ]
    }
    """.data(using: .utf8)!
}
