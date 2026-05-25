// Tests/SwiftGeminiInteractionsTests/DecodingTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class DecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testTextContentDecoding() throws {
        let json = """
        {"type": "text", "text": "Hello world"}
        """.data(using: .utf8)!
        let content = try decoder.decode(Content.self, from: json)
        if case .text(let text, _) = content {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected .text case")
        }
    }

    func testFileCitationDecoding() throws {
        let json = """
        {
            "type": "file_citation",
            "document_uri": "gs://bucket/file.pdf",
            "file_name": "file.pdf",
            "source": "upload",
            "start_index": 0,
            "end_index": 10
        }
        """.data(using: .utf8)!
        let annotation = try decoder.decode(Annotation.self, from: json)
        if case .fileCitation(let uri, let name, _, _, _, _) = annotation {
            XCTAssertEqual(uri, "gs://bucket/file.pdf")
            XCTAssertEqual(name, "file.pdf")
        } else {
            XCTFail("Expected .fileCitation case")
        }
    }

    func testUsageDecoding() throws {
        let json = """
        {
            "total_input_tokens": 10,
            "total_output_tokens": 20,
            "total_thought_tokens": 5,
            "total_cached_tokens": 0,
            "total_tool_use_tokens": 3,
            "total_tokens": 38,
            "input_tokens_by_modality": [{"modality": "text", "tokens": 10}]
        }
        """.data(using: .utf8)!
        let usage = try decoder.decode(Usage.self, from: json)
        XCTAssertEqual(usage.totalInputTokens, 10)
        XCTAssertEqual(usage.totalOutputTokens, 20)
        XCTAssertEqual(usage.totalThoughtTokens, 5)
        XCTAssertEqual(usage.totalCachedTokens, 0)
        XCTAssertEqual(usage.totalToolUseTokens, 3)
        XCTAssertEqual(usage.totalTokens, 38)
        XCTAssertEqual(usage.inputTokensByModality.first?.modality, "text")
        XCTAssertEqual(usage.inputTokensByModality.first?.tokens, 10)
    }

    func testModelOutputStepDecoding() throws {
        let json = """
        {
            "type": "model_output",
            "content": [{"type": "text", "text": "Hi there"}]
        }
        """.data(using: .utf8)!
        let step = try decoder.decode(Step.self, from: json)
        if case .modelOutput(let content) = step {
            if case .text(let text, _) = content.first {
                XCTAssertEqual(text, "Hi there")
            } else { XCTFail("Expected text content") }
        } else { XCTFail("Expected .modelOutput") }
    }

    func testFunctionCallStepDecoding() throws {
        let json = """
        {"type": "function_call", "id": "call-1", "name": "myFn", "arguments": "{\\"x\\": 1}"}
        """.data(using: .utf8)!
        let step = try decoder.decode(Step.self, from: json)
        if case .functionCall(let id, let name, let args) = step {
            XCTAssertEqual(id, "call-1")
            XCTAssertEqual(name, "myFn")
            XCTAssertEqual(args, "{\"x\": 1}")
        } else { XCTFail("Expected .functionCall") }
    }

    func testUnknownStepTypeThrows() {
        let json = """
        {"type": "unknown_future_type", "id": "x"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(Step.self, from: json))
    }

    func testThoughtStepDecodingWithSummary() throws {
        let json = """
        {
            "type": "thought",
            "content": [{"type": "text", "text": "Thinking..."}],
            "summary": "I thought about X"
        }
        """.data(using: .utf8)!
        let step = try decoder.decode(Step.self, from: json)
        if case .thought(let content, let summary) = step {
            XCTAssertEqual(summary, "I thought about X")
            if case .text(let text, _) = content.first {
                XCTAssertEqual(text, "Thinking...")
            } else { XCTFail("Expected text content") }
        } else { XCTFail("Expected .thought") }
    }

    func testThoughtStepDecodingWithoutSummary() throws {
        let json = """
        {"type": "thought", "content": [{"type": "text", "text": "Hmm"}]}
        """.data(using: .utf8)!
        let step = try decoder.decode(Step.self, from: json)
        if case .thought(_, let summary) = step {
            XCTAssertNil(summary)
        } else { XCTFail("Expected .thought") }
    }

    func testUrlContextResultDecoding() throws {
        let json = """
        {"type": "url_context_result", "call_id": "ctx-1", "content": "Page content here"}
        """.data(using: .utf8)!
        let step = try decoder.decode(Step.self, from: json)
        if case .urlContextResult(let callId, let content) = step {
            XCTAssertEqual(callId, "ctx-1")
            XCTAssertEqual(content, "Page content here")
        } else { XCTFail("Expected .urlContextResult") }
    }

    func testFunctionCallRoundtrip() throws {
        let original = Step.functionCall(id: "c-1", name: "myFn", arguments: "{\"key\": \"value\"}")
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(Step.self, from: data)
        if case .functionCall(let id, let name, let args) = decoded {
            XCTAssertEqual(id, "c-1")
            XCTAssertEqual(name, "myFn")
            XCTAssertEqual(args, "{\"key\": \"value\"}")
        } else { XCTFail("Roundtrip should produce .functionCall") }
    }

    func testFunctionToolDecoding() throws {
        let json = """
        {
            "type": "function",
            "name": "myFn",
            "description": "Does something",
            "parameters": {"type": "object", "properties": {}}
        }
        """.data(using: .utf8)!
        let tool = try decoder.decode(InteractionTool.self, from: json)
        if case .function(let name, let description, _) = tool {
            XCTAssertEqual(name, "myFn")
            XCTAssertEqual(description, "Does something")
        } else { XCTFail("Expected .function") }
    }

    func testGoogleSearchToolDecoding() throws {
        let json = "{\"type\": \"google_search\"}".data(using: .utf8)!
        let tool = try decoder.decode(InteractionTool.self, from: json)
        if case .googleSearch = tool { } else { XCTFail("Expected .googleSearch") }
    }

    func testFileSearchToolDecoding() throws {
        let json = """
        {
            "type": "file_search",
            "file_search_store_names": ["myStore"],
            "top_k": 5
        }
        """.data(using: .utf8)!
        let tool = try decoder.decode(InteractionTool.self, from: json)
        if case .fileSearch(let storeNames, let topK, _) = tool {
            XCTAssertEqual(storeNames, ["myStore"])
            XCTAssertEqual(topK, 5)
        } else { XCTFail("Expected .fileSearch") }
    }

    func testFunctionToolWithNumberConstraintsRoundtrip() throws {
        // This verifies the integer-format minimum/maximum bug fix
        let json = """
        {
            "type": "function",
            "name": "fn",
            "description": "d",
            "parameters": {
                "type": "object",
                "properties": {
                    "count": {"type": "number", "minimum": 1, "maximum": 100}
                }
            }
        }
        """.data(using: .utf8)!
        let tool = try decoder.decode(InteractionTool.self, from: json)
        if case .function(_, _, let params) = tool {
            if case .object(let props, _) = params,
               let countProp = props.first(where: { $0.0 == "count" }) {
                if case .number(_, let min, let max) = countProp.1 {
                    XCTAssertEqual(min, 1.0, "minimum should be 1.0 not nil")
                    XCTAssertEqual(max, 100.0, "maximum should be 100.0 not nil")
                } else { XCTFail("Expected .number schema") }
            } else { XCTFail("Expected .object schema with count property") }
        } else { XCTFail("Expected .function") }
    }

    func testTextResponseFormatDecoding() throws {
        let json = """
        {"type": "text", "mime_type": "application/json"}
        """.data(using: .utf8)!
        let format = try decoder.decode(ResponseFormat.self, from: json)
        if case .text(let mimeType, _) = format {
            XCTAssertEqual(mimeType, "application/json")
        } else { XCTFail("Expected .text ResponseFormat") }
    }

    func testImageResponseFormatDecoding() throws {
        let json = """
        {"type": "image", "mime_type": "image/png", "aspect_ratio": "16:9", "delivery": "inline"}
        """.data(using: .utf8)!
        let format = try decoder.decode(ResponseFormat.self, from: json)
        if case .image(let mimeType, let aspectRatio, _, let delivery) = format {
            XCTAssertEqual(mimeType, "image/png")
            XCTAssertEqual(aspectRatio, "16:9")
            XCTAssertEqual(delivery, .inline)
        } else { XCTFail("Expected .image ResponseFormat") }
    }

    func testAudioResponseFormatDecoding() throws {
        let json = """
        {"type": "audio", "mime_type": "audio/mp3", "sample_rate": 44100, "bit_rate": 128, "delivery": "uri"}
        """.data(using: .utf8)!
        let format = try decoder.decode(ResponseFormat.self, from: json)
        if case .audio(let mimeType, let sampleRate, let bitRate, let delivery) = format {
            XCTAssertEqual(mimeType, .mp3)
            XCTAssertEqual(sampleRate, 44100)
            XCTAssertEqual(bitRate, 128)
            XCTAssertEqual(delivery, .uri)
        } else { XCTFail("Expected .audio ResponseFormat") }
    }

    func testEnvironmentNetworkDisabledDecoding() throws {
        let json = "\"disabled\"".data(using: .utf8)!
        let network = try decoder.decode(EnvironmentNetwork.self, from: json)
        if case .disabled = network { } else { XCTFail("Expected .disabled") }
    }

    func testEnvironmentNetworkAllowlistDecoding() throws {
        let json = """
        {"allowlist": [{"domain": "pypi.org"}]}
        """.data(using: .utf8)!
        let network = try decoder.decode(EnvironmentNetwork.self, from: json)
        if case .allowlist(let entries) = network {
            XCTAssertEqual(entries.first?.domain, "pypi.org")
        } else { XCTFail("Expected .allowlist") }
    }

    func testEnvironmentSourceInlineDecoding() throws {
        let json = """
        {"type": "inline", "target": "/workspace/main.py", "content": "print('hello')"}
        """.data(using: .utf8)!
        let source = try decoder.decode(EnvironmentSource.self, from: json)
        if case .inline(let target, let content) = source {
            XCTAssertEqual(target, "/workspace/main.py")
            XCTAssertEqual(content, "print('hello')")
        } else { XCTFail("Expected .inline") }
    }

    func testEnvironmentSourceUnknownTypeThrows() {
        let json = """
        {"type": "unknown_source_type", "target": "/path"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(EnvironmentSource.self, from: json))
    }

    func testEnvironmentConfigDecoding() throws {
        let json = """
        {
            "type": "remote",
            "sources": [{"type": "inline", "target": "/main.py", "content": "x = 1"}],
            "network": "disabled"
        }
        """.data(using: .utf8)!
        let env = try decoder.decode(EnvironmentConfig.self, from: json)
        XCTAssertEqual(env.sources?.count, 1)
        if case .disabled = env.network { } else { XCTFail("Expected .disabled network") }
    }

    func testInteractionDecoding() throws {
        let json = """
        {
            "id": "v1_abc123",
            "object": "interaction",
            "model": "gemini-3-flash-preview",
            "status": "completed",
            "created": "2026-05-24T10:00:00Z",
            "steps": [
                {"type": "user_input", "content": [{"type": "text", "text": "Hello"}]},
                {"type": "model_output", "content": [{"type": "text", "text": "Hi there!"}]}
            ],
            "usage": {
                "total_input_tokens": 5, "total_output_tokens": 10,
                "total_thought_tokens": 0, "total_cached_tokens": 0,
                "total_tool_use_tokens": 0, "total_tokens": 15,
                "input_tokens_by_modality": []
            }
        }
        """.data(using: .utf8)!
        let interaction = try decoder.decode(Interaction.self, from: json)
        XCTAssertEqual(interaction.id, "v1_abc123")
        XCTAssertEqual(interaction.status, .completed)
        XCTAssertEqual(interaction.steps.count, 2)
        XCTAssertEqual(interaction.outputText, "Hi there!")
        XCTAssertFalse(interaction.requiresAction)
        XCTAssertTrue(interaction.isComplete)
    }

    func testInteractionRequiresActionConvenience() throws {
        let json = """
        {
            "id": "v1_xyz",
            "object": "interaction",
            "model": "gemini-3-flash-preview",
            "status": "requires_action",
            "created": "2026-05-24T10:00:00Z",
            "steps": [
                {"type": "function_call", "id": "call-1", "name": "myFn", "arguments": "{}"}
            ]
        }
        """.data(using: .utf8)!
        let interaction = try decoder.decode(Interaction.self, from: json)
        XCTAssertTrue(interaction.requiresAction)
        XCTAssertFalse(interaction.isComplete)
        XCTAssertEqual(interaction.functionCalls.count, 1)
        XCTAssertNil(interaction.outputText)
    }

    func testClientSendReturnsInteraction() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Api-Revision"), "2026-05-20")
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON())
        }
        let client = makeTestClient()
        var request = InteractionRequest(input: .text("Hello"))
        request.model = "gemini-3-flash-preview"
        let interaction = try await client.send(request)
        XCTAssertEqual(interaction.id, "v1_test")
        XCTAssertEqual(interaction.status, .completed)
    }

    func testClientSend429ThrowsRateLimit() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = makeTestClient()
        var request = InteractionRequest(input: .text("Hello"))
        request.model = "gemini-3-flash-preview"
        do {
            _ = try await client.send(request)
            XCTFail("Should have thrown")
        } catch GeminiInteractionsError.rateLimitExceeded {
            // pass
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testClientGetReturnsInteraction() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertTrue(request.url!.path.hasSuffix("/v1_test"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON())
        }
        let client = makeTestClient()
        let interaction = try await client.get(id: "v1_test")
        XCTAssertEqual(interaction.id, "v1_test")
    }

    func testClientDeleteSends204() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = makeTestClient()
        try await client.delete(id: "v1_test")  // should not throw
    }

    func testClientCancelSendsPostToCancel() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url!.path.hasSuffix("/cancel"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON(status: "cancelled"))
        }
        let client = makeTestClient()
        try await client.cancel(id: "v1_test")  // should not throw
    }

    func testClientNetworkErrorWrapped() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = makeTestClient()
        let request = InteractionRequest(input: .text("Hello"))
        do {
            _ = try await client.send(request)
            XCTFail("Should have thrown networkError")
        } catch GeminiInteractionsError.networkError {
            // pass
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}
