// Tests/SwiftGeminiInteractionsTests/SSEParserTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class SSEParserTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testInteractionCreatedEventDecoding() throws {
        let json = """
        {
            "event_type": "interaction.created",
            "interaction": {
                "id": "v1_abc", "object": "interaction",
                "model": "gemini-3-flash-preview",
                "status": "in_progress", "created": "2026-05-24T10:00:00Z", "steps": []
            }
        }
        """.data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .interactionCreated(let interaction) = event {
            XCTAssertEqual(interaction.id, "v1_abc")
        } else { XCTFail("Expected .interactionCreated") }
    }

    func testStepStartEventDecoding() throws {
        let json = """
        {
            "event_type": "step.start",
            "index": 0,
            "step": {"type": "model_output"}
        }
        """.data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .stepStart(let stepType, let index) = event {
            XCTAssertEqual(stepType, "model_output")
            XCTAssertEqual(index, 0)
        } else { XCTFail("Expected .stepStart") }
    }

    func testStepDeltaTextDecoding() throws {
        let json = """
        {
            "event_type": "step.delta",
            "index": 0,
            "delta": {"type": "text", "text": "Hello"}
        }
        """.data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .stepDelta(let delta, let index) = event {
            XCTAssertEqual(index, 0)
            if case .text(let text) = delta {
                XCTAssertEqual(text, "Hello")
            } else { XCTFail("Expected .text delta") }
        } else { XCTFail("Expected .stepDelta") }
    }

    func testStepDeltaFunctionCallArgumentsDecoding() throws {
        let json = """
        {
            "event_type": "step.delta",
            "index": 1,
            "delta": {"type": "function_call_arguments", "delta": "{\\"x\\"", "call_id": "call-1"}
        }
        """.data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .stepDelta(let delta, _) = event,
           case .functionCallArguments(let d, let callId) = delta {
            XCTAssertEqual(callId, "call-1")
            XCTAssertEqual(d, "{\"x\"")
        } else { XCTFail("Expected .stepDelta with .functionCallArguments delta") }
    }

    func testStepStopEventDecoding() throws {
        let json = """
        {"event_type": "step.stop", "index": 0}
        """.data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .stepStop(let index) = event {
            XCTAssertEqual(index, 0)
        } else { XCTFail("Expected .stepStop") }
    }

    func testInteractionCompletedEventDecoding() throws {
        let json = """
        {
            "event_type": "interaction.completed",
            "interaction": {
                "id": "v1_abc", "object": "interaction",
                "model": "gemini-3-flash-preview",
                "status": "completed", "created": "2026-05-24T10:00:00Z",
                "steps": [{"type": "model_output", "content": [{"type": "text", "text": "Done"}]}]
            }
        }
        """.data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .interactionCompleted(let interaction) = event {
            XCTAssertEqual(interaction.status, .completed)
            XCTAssertEqual(interaction.outputText, "Done")
        } else { XCTFail("Expected .interactionCompleted") }
    }

    func testUnknownEventTypeIsDropped() throws {
        let json = """
        {"event_type": "future.unknown", "foo": "bar"}
        """.data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .unknown = event { } else { XCTFail("Expected .unknown for unrecognised event_type") }
    }

    func testErrorEventDecoding() throws {
        let json = """
        {"event_type": "error", "message": "Something went wrong"}
        """.data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .error(let msg) = event {
            XCTAssertEqual(msg, "Something went wrong")
        } else { XCTFail("Expected .error") }
    }

    func testSSEParserProducesEventsFromByteStream() async throws {
        let sseData = """
        data: {"event_type": "interaction.created", "interaction": {"id": "v1_abc", "object": "interaction", "model": "gemini-3-flash-preview", "status": "in_progress", "created": "2026-05-24T10:00:00Z", "steps": []}}

        data: {"event_type": "step.start", "index": 0, "step": {"type": "model_output"}}

        data: {"event_type": "step.delta", "index": 0, "delta": {"type": "text", "text": "Hi"}}

        data: {"event_type": "step.stop", "index": 0}

        data: {"event_type": "interaction.completed", "interaction": {"id": "v1_abc", "object": "interaction", "model": "gemini-3-flash-preview", "status": "completed", "created": "2026-05-24T10:00:00Z", "steps": [{"type": "model_output", "content": [{"type": "text", "text": "Hi"}]}]}}

        """.data(using: .utf8)!

        var events: [InteractionStreamEvent] = []
        for try await event in parseSSE(from: AsyncThrowingStream { continuation in
            continuation.yield(sseData)
            continuation.finish()
        }) {
            events.append(event)
        }
        XCTAssertEqual(events.count, 5)
        if case .interactionCreated = events[0] { } else { XCTFail("Expected .interactionCreated first") }
        if case .stepStart(_, let idx) = events[1] { XCTAssertEqual(idx, 0) } else { XCTFail("Expected .stepStart") }
        if case .stepDelta(let delta, _) = events[2], case .text(let t) = delta { XCTAssertEqual(t, "Hi") } else { XCTFail("Expected text delta") }
        if case .interactionCompleted = events[4] { } else { XCTFail("Expected .interactionCompleted last") }
    }

    func testStreamMethodForwardsSSEEvents() async throws {
        let ssePayload = """
        data: {"event_type": "interaction.created", "interaction": {"id": "v1_s", "object": "interaction", "model": "gemini-3-flash-preview", "status": "in_progress", "created": "2026-05-24T10:00:00Z", "steps": []}}

        data: {"event_type": "interaction.completed", "interaction": {"id": "v1_s", "object": "interaction", "model": "gemini-3-flash-preview", "status": "completed", "created": "2026-05-24T10:00:00Z", "steps": [{"type": "model_output", "content": [{"type": "text", "text": "Hello!"}]}]}}

        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, ssePayload)
        }
        let client = makeTestClient()
        var request = InteractionRequest(input: .text("Hello"))
        request.model = "gemini-3-flash-preview"
        request.stream = true

        var events: [InteractionStreamEvent] = []
        for try await event in client.stream(request) {
            events.append(event)
        }
        let nonUnknown = events.filter { if case .unknown = $0 { return false }; return true }
        XCTAssertEqual(nonUnknown.count, 2)
    }

    func testResumeStreamSendsCorrectQueryParams() async throws {
        MockURLProtocol.requestHandler = { request in
            let urlString = request.url!.absoluteString
            XCTAssertTrue(urlString.contains("stream=true"))
            XCTAssertTrue(urlString.contains("last_event_id=evt-42"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let client = makeTestClient()
        var count = 0
        for try await _ in client.resumeStream(id: "v1_abc", lastEventId: "evt-42") {
            count += 1
        }
        XCTAssertEqual(count, 0)  // empty SSE body produces no events
    }
}
