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
}
