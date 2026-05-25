// Tests/SwiftGeminiInteractionsTests/DecodingTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class DecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

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
