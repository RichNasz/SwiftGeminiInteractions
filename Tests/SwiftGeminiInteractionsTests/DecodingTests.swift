// Tests/SwiftGeminiInteractionsTests/DecodingTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class DecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

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
}
