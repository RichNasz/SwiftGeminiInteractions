import XCTest
@testable import SwiftGeminiInteractions

final class EncodingTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func testInteractionStatusRawValues() {
        XCTAssertEqual(InteractionStatus.inProgress.rawValue, "in_progress")
        XCTAssertEqual(InteractionStatus.requiresAction.rawValue, "requires_action")
        XCTAssertEqual(InteractionStatus.budgetExceeded.rawValue, "budget_exceeded")
    }

    func testServiceTierRawValues() {
        XCTAssertEqual(ServiceTier.flex.rawValue, "flex")
        XCTAssertEqual(ServiceTier.priority.rawValue, "priority")
    }

    func testResponseModalityRawValues() {
        XCTAssertEqual(ResponseModality.text.rawValue, "text")
        XCTAssertEqual(ResponseModality.document.rawValue, "document")
    }

    func testThinkingLevelRawValues() {
        XCTAssertEqual(ThinkingLevel.none.rawValue, "none")
        XCTAssertEqual(ThinkingLevel.high.rawValue, "high")
    }

    func testThinkingSummariesRawValues() {
        XCTAssertEqual(ThinkingSummaries.enabled.rawValue, "enabled")
        XCTAssertEqual(ThinkingSummaries.disabled.rawValue, "disabled")
    }

    func testToolChoiceModeRawValues() {
        XCTAssertEqual(ToolChoiceMode.auto.rawValue, "auto")
        XCTAssertEqual(ToolChoiceMode.required.rawValue, "required")
    }

    func testToolChoiceConfigEncoding() throws {
        let config = ToolChoiceConfig(mode: .auto, allowedTools: ["myTool"])
        let data = try encoder.encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["mode"] as? String, "auto")
        XCTAssertEqual((json["allowed_tools"] as? [String])?.first, "myTool")
    }

    func testTextContentEncoding() throws {
        let content = Content.text("Hello world", annotations: nil)
        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "text")
        XCTAssertEqual(json["text"] as? String, "Hello world")
    }

    func testImageContentEncoding() throws {
        let imageData = Data([0xFF, 0xD8])
        let content = Content.image(data: imageData, mimeType: "image/jpeg", uri: nil)
        let data = try encoder.encode(content)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "image")
        XCTAssertEqual(json["mime_type"] as? String, "image/jpeg")
        XCTAssertNotNil(json["data"])
    }

    func testUrlCitationEncoding() throws {
        let annotation = Annotation.urlCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 5)
        let data = try encoder.encode(annotation)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "url_citation")
        XCTAssertEqual(json["url"] as? String, "https://example.com")
    }

    func testUsageEncoding() throws {
        let usage = Usage(
            totalInputTokens: 10,
            totalOutputTokens: 20,
            totalThoughtTokens: 5,
            totalCachedTokens: 0,
            totalToolUseTokens: 3,
            totalTokens: 38,
            inputTokensByModality: [ModalityTokens(modality: "text", tokens: 10)]
        )
        let data = try encoder.encode(usage)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["total_input_tokens"] as? Int, 10)
        XCTAssertEqual(json["total_output_tokens"] as? Int, 20)
        XCTAssertEqual(json["total_thought_tokens"] as? Int, 5)
        XCTAssertEqual(json["total_cached_tokens"] as? Int, 0)
        XCTAssertEqual(json["total_tool_use_tokens"] as? Int, 3)
        XCTAssertEqual(json["total_tokens"] as? Int, 38)
        let modalities = json["input_tokens_by_modality"] as? [[String: Any]]
        XCTAssertEqual(modalities?.first?["modality"] as? String, "text")
        XCTAssertEqual(modalities?.first?["tokens"] as? Int, 10)
    }
}
