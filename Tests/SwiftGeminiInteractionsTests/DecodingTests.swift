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
}
