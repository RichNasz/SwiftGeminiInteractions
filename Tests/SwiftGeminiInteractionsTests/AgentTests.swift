// Tests/SwiftGeminiInteractionsTests/AgentTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class AgentTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testAgentSendWithNoToolsReturnsOutputText() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON(id: "v1_a1", status: "completed"))
        }
        let client = makeTestClient()
        let agent = try Agent(client: client, model: "gemini-3-flash-preview")
        let reply = try await agent.send("Hello")
        XCTAssertFalse(reply.isEmpty)
        let transcript = await agent.transcript
        XCTAssertEqual(transcript.count, 2)
        if case .userMessage(let msg) = transcript[0] { XCTAssertEqual(msg, "Hello") }
        else { XCTFail("First transcript entry should be userMessage") }
        if case .assistantMessage = transcript[1] { }
        else { XCTFail("Second transcript entry should be assistantMessage") }
    }

    func testAgentChainsViaLastInteractionId() async throws {
        final class RequestStore: @unchecked Sendable {
            var bodies: [[String: Any]] = []
        }
        let store = RequestStore()
        MockURLProtocol.requestHandler = { request in
            let bodyData = requestBodyData(from: request) ?? request.httpBody ?? Data()
            if let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                store.bodies.append(body)
            }
            let n = store.bodies.count
            let json = makeInteractionJSON(id: "v1_\(n)")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = makeTestClient()
        let agent = try Agent(client: client, model: "gemini-3-flash-preview")
        _ = try await agent.send("First")
        _ = try await agent.send("Second")
        guard store.bodies.count >= 2 else {
            XCTFail("Expected 2 request bodies, got \(store.bodies.count)")
            return
        }
        XCTAssertEqual(store.bodies[1]["previous_interaction_id"] as? String, "v1_1")
        XCTAssertEqual(store.bodies[1]["store"] as? Bool, true)
    }

    func testAgentResetClearsState() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON(id: "v1_a1"))
        }
        let client = makeTestClient()
        let agent = try Agent(client: client, model: "gemini-3-flash-preview")
        _ = try await agent.send("Hello")
        await agent.reset()
        let id = await agent.lastInteractionId
        let transcript = await agent.transcript
        XCTAssertNil(id)
        XCTAssertTrue(transcript.isEmpty)
    }

    func testAgentThrowsOnDuplicateToolNames() throws {
        let client = makeTestClient()
        let schema = JSONSchemaValue.object(properties: [], required: [])
        XCTAssertThrowsError(
            try Agent(client: client, model: "gemini-3-flash-preview") {
                AgentTool(tool: .function(name: "fn", description: "d", parameters: schema), handler: { _ in "ok" })
                AgentTool(tool: .function(name: "fn", description: "d2", parameters: schema), handler: { _ in "ok2" })
            }
        )
    }

    func testAgentNamedAgentInitSetsAgentField() async throws {
        final class BodyCapture: @unchecked Sendable {
            var body: [String: Any]?
        }
        let capture = BodyCapture()
        MockURLProtocol.requestHandler = { request in
            let bodyData = requestBodyData(from: request) ?? request.httpBody ?? Data()
            capture.body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON())
        }
        let client = makeTestClient()
        let agent = try Agent(client: client, agent: "deep-research-pro-preview-04-2026")
        _ = try await agent.send("Research quantum computing")
        XCTAssertEqual(capture.body?["agent"] as? String, "deep-research-pro-preview-04-2026")
        XCTAssertNil(capture.body?["model"])
    }
}
