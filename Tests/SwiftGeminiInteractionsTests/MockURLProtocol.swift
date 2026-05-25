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

/// Reads the body from a URLRequest, handling both httpBody and httpBodyStream.
func requestBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let bytesRead = stream.read(buffer, maxLength: bufferSize)
        if bytesRead > 0 { data.append(buffer, count: bytesRead) }
        else { break }
    }
    return data.isEmpty ? nil : data
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
