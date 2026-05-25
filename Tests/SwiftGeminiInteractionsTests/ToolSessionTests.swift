// Tests/SwiftGeminiInteractionsTests/ToolSessionTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class ToolSessionTests: XCTestCase {

    private func setHandlers(_ responses: [(status: String, steps: String, id: String)]) {
        var queue = responses
        MockURLProtocol.requestHandler = { request in
            let next = queue.removeFirst()
            let json = """
            {
                "id": "\(next.id)", "object": "interaction",
                "model": "gemini-3-flash-preview",
                "status": "\(next.status)", "created": "2026-05-24T10:00:00Z",
                "steps": [\(next.steps)]
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testRunCompletesImmediately() async throws {
        let modelOutputStep = #"{"type":"model_output","content":[{"type":"text","text":"Done"}]}"#
        setHandlers([("completed", modelOutputStep, "v1_1")])
        let client = makeTestClient()
        let session = ToolSession(
            client: client,
            tools: [],
            handlers: [:],
            maxIterations: 5
        )
        let result = try await session.run(
            model: "gemini-3-flash-preview",
            input: [User("Hello")],
            configParams: []
        )
        XCTAssertEqual(result.interaction.status, .completed)
        XCTAssertEqual(result.iterations, 1)
        XCTAssertTrue(result.log.isEmpty)
    }

    func testRunExecutesToolAndCompletesOnSecondIteration() async throws {
        let functionCallStep = #"{"type":"function_call","id":"call-1","name":"echo","arguments":"{\"msg\":\"hello\"}"}"#
        let modelOutputStep = #"{"type":"model_output","content":[{"type":"text","text":"echo: hello"}]}"#
        setHandlers([
            ("requires_action", functionCallStep, "v1_1"),
            ("completed", modelOutputStep, "v1_2")
        ])
        let client = makeTestClient()
        final class Box: @unchecked Sendable { var value: String? }
        let capturedBox = Box()
        let session = ToolSession(
            client: client,
            tools: [.function(name: "echo", description: "echoes", parameters: .object(properties: [], required: []))],
            handlers: ["echo": { args in
                capturedBox.value = args
                let decoded = try JSONDecoder().decode([String: String].self, from: args.data(using: .utf8)!)
                return "echo: \(decoded["msg"] ?? "")"
            }],
            maxIterations: 5
        )
        let result = try await session.run(
            model: "gemini-3-flash-preview",
            input: [User("Hello")],
            configParams: []
        )
        XCTAssertEqual(result.interaction.status, .completed)
        XCTAssertEqual(result.iterations, 2)
        XCTAssertEqual(result.log.count, 1)
        XCTAssertEqual(result.log.first?.name, "echo")
        XCTAssertEqual(result.log.first?.result, "echo: hello")
        XCTAssertNotNil(capturedBox.value)
    }

    func testRunThrowsWhenMaxIterationsExceeded() async {
        MockURLProtocol.requestHandler = { request in
            let json = """
            {
                "id": "v1_loop", "object": "interaction",
                "model": "gemini-3-flash-preview",
                "status": "requires_action", "created": "2026-05-24T10:00:00Z",
                "steps": [{"type":"function_call","id":"call-x","name":"noop","arguments":"{}"}]
            }
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = makeTestClient()
        let session = ToolSession(
            client: client,
            tools: [.function(name: "noop", description: "does nothing", parameters: .object(properties: [], required: []))],
            handlers: ["noop": { _ in "ok" }],
            maxIterations: 2
        )
        do {
            _ = try await session.run(model: "gemini-3-flash-preview", input: [User("Go")], configParams: [])
            XCTFail("Should have thrown maxIterationsExceeded")
        } catch GeminiInteractionsError.maxIterationsExceeded(let n) {
            XCTAssertEqual(n, 2)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testRunSetsStoreTrueAutomatically() async throws {
        final class BodyBox: @unchecked Sendable { var value: [String: Any]? }
        let bodyBox = BodyBox()
        MockURLProtocol.requestHandler = { request in
            if let bodyData = requestBodyData(from: request) {
                bodyBox.value = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            }
            let json = makeInteractionJSON()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = makeTestClient()
        let session = ToolSession(client: client, tools: [], handlers: [:], maxIterations: 5)
        _ = try await session.run(model: "gemini-3-flash-preview", input: [User("Hi")], configParams: [])
        XCTAssertEqual(bodyBox.value?["store"] as? Bool, true)
    }

    func testRunChainsViaPreviousInteractionId() async throws {
        final class RequestLog: @unchecked Sendable {
            var bodies: [[String: Any]] = []
        }
        let log = RequestLog()
        MockURLProtocol.requestHandler = { request in
            if let bodyData = requestBodyData(from: request),
               let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                log.bodies.append(body)
            }
            let iteration = log.bodies.count
            let status = iteration == 1 ? "requires_action" : "completed"
            let steps = iteration == 1
                ? #"{"type":"function_call","id":"call-1","name":"fn","arguments":"{}"}"#
                : #"{"type":"model_output","content":[{"type":"text","text":"done"}]}"#
            let id = "v1_\(iteration)"
            let json = """
            {"id":"\(id)","object":"interaction","model":"gemini-3-flash-preview",
             "status":"\(status)","created":"2026-05-24T10:00:00Z","steps":[\(steps)]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = makeTestClient()
        let session = ToolSession(
            client: client,
            tools: [.function(name: "fn", description: "d", parameters: .object(properties: [], required: []))],
            handlers: ["fn": { _ in "result" }],
            maxIterations: 5
        )
        _ = try await session.run(model: "gemini-3-flash-preview", input: [User("Go")], configParams: [])
        XCTAssertEqual(log.bodies.count, 2, "Expected 2 requests to have been made")
        if log.bodies.count >= 2 {
            XCTAssertEqual(log.bodies[1]["previous_interaction_id"] as? String, "v1_1")
        }
    }
}
