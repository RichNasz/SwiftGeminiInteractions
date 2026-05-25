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
            "step_type": "model_output"
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
}
