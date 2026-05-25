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

    func testUserInputStepEncoding() throws {
        let step = Step.userInput(content: [.text("Hello", annotations: nil)])
        let data = try encoder.encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "user_input")
        let content = json["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["text"] as? String, "Hello")
    }

    func testFunctionCallStepEncoding() throws {
        let step = Step.functionCall(id: "call-1", name: "myFn", arguments: "{\"x\": 1}")
        let data = try encoder.encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "function_call")
        XCTAssertEqual(json["id"] as? String, "call-1")
        XCTAssertEqual(json["name"] as? String, "myFn")
        XCTAssertEqual(json["arguments"] as? String, "{\"x\": 1}")
    }

    func testFunctionResultStepEncoding() throws {
        let step = Step.functionResult(callId: "call-1", result: "42", name: "myFn", isError: false)
        let data = try encoder.encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "function_result")
        XCTAssertEqual(json["call_id"] as? String, "call-1")
        XCTAssertEqual(json["result"] as? String, "42")
    }

    func testGoogleSearchCallStepEncoding() throws {
        let step = Step.googleSearchCall(id: "search-1")
        let data = try encoder.encode(step)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "google_search_call")
        XCTAssertEqual(json["id"] as? String, "search-1")
    }

    func testFunctionToolEncoding() throws {
        let schema = JSONSchemaValue.object(properties: [("x", .number())], required: [])
        let tool = InteractionTool.function(name: "myFn", description: "Does something", parameters: schema)
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "function")
        XCTAssertEqual(json["name"] as? String, "myFn")
        XCTAssertNotNil(json["parameters"])
    }

    func testGoogleSearchToolEncoding() throws {
        let tool = InteractionTool.googleSearch
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "google_search")
        XCTAssertNil(json["name"])
    }

    func testFileSearchToolEncoding() throws {
        let tool = InteractionTool.fileSearch(storeNames: ["myStore"], topK: 5, metadataFilter: nil)
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "file_search")
        XCTAssertEqual((json["file_search_store_names"] as? [String])?.first, "myStore")
        XCTAssertEqual(json["top_k"] as? Int, 5)
    }

    func testGoogleMapsToolEncoding() throws {
        let tool = InteractionTool.googleMaps(latitude: 37.7749, longitude: -122.4194, enableWidget: true)
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "google_maps")
        let lat = json["latitude"] as? Double
        XCTAssertNotNil(lat)
        XCTAssertEqual(lat ?? 0.0, 37.7749, accuracy: 0.0001)
    }

    func testInteractionInputTextEncoding() throws {
        let input = InteractionInput.text("Hello!")
        let data = try encoder.encode(input)
        let str = String(data: data, encoding: .utf8)!
        XCTAssertEqual(str, "\"Hello!\"")
    }

    func testInteractionInputStepsEncoding() throws {
        let input = InteractionInput.steps([.userInput(content: [.text("Hi", annotations: nil)])])
        let data = try encoder.encode(input)
        let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertNotNil(arr)
        XCTAssertEqual(arr?.first?["type"] as? String, "user_input")
    }

    func testGenerationConfigEncoding() throws {
        let config = GenerationConfig(temperature: 0.7, topP: 0.9, maxOutputTokens: 1024,
                                       seed: nil, stopSequences: nil, thinkingLevel: .medium,
                                       thinkingSummaries: nil, toolChoice: nil)
        let data = try encoder.encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        if let temp = json["temperature"] as? Double {
            XCTAssertEqual(temp, 0.7, accuracy: 0.001)
        }
        XCTAssertEqual(json["max_output_tokens"] as? Int, 1024)
        XCTAssertEqual(json["thinking_level"] as? String, "medium")
    }

    func testInteractionRequestEncoding() throws {
        var request = InteractionRequest(input: .text("Hello"))
        request.model = "gemini-3-flash-preview"
        request.store = true
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "gemini-3-flash-preview")
        XCTAssertEqual(json["store"] as? Bool, true)
        XCTAssertNotNil(json["input"])
    }

    func testTextResponseFormatEncoding() throws {
        let format = ResponseFormat.text(mimeType: "application/json", schema: nil)
        let data = try encoder.encode(format)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "text")
        XCTAssertEqual(json["mime_type"] as? String, "application/json")
    }

    func testImageResponseFormatEncoding() throws {
        let format = ResponseFormat.image(mimeType: "image/png", aspectRatio: "16:9", imageSize: nil, delivery: .inline)
        let data = try encoder.encode(format)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "image")
        XCTAssertEqual(json["mime_type"] as? String, "image/png")
        XCTAssertEqual(json["delivery"] as? String, "inline")
    }

    func testAudioResponseFormatEncoding() throws {
        let format = ResponseFormat.audio(mimeType: .mp3, sampleRate: 44100, bitRate: 128, delivery: .uri)
        let data = try encoder.encode(format)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "audio")
        XCTAssertEqual(json["mime_type"] as? String, "audio/mp3")
        XCTAssertEqual(json["sample_rate"] as? Int, 44100)
    }
}
