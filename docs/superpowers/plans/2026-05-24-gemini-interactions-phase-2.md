# SwiftGeminiInteractions — Implementation Plan (Phase 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SSE streaming, the tool-calling loop (`ToolSession`), the stateful `Agent` actor, and all open-source documentation. Requires Phase 1 to be complete and all Phase 1 tests passing.

**Architecture:** Streaming extends `InteractionsClient` with SSE parsing. `ToolSession` (in `ToolSession.swift`) owns the `previous_interaction_id` tool loop with parallel handler execution. `Agent` (in `Agent.swift`) is a stateful actor that wraps `ToolSession` and tracks conversation history. Documentation covers spec files, CLAUDE.md, README, examples, and guide docs.

**Tech Stack:** Swift 6.3, SwiftLLMToolMacros, XCTest, AsyncThrowingStream, ContinuousClock.

**Prerequisite:** Run `swift test` — all Phase 1 tests must pass before starting Phase 2.

---

## Task 16: InteractionStreamEvent and InteractionStreamDelta types

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Create: `Tests/SwiftGeminiInteractionsTests/SSEParserTests.swift`

- [ ] **Step 1: Write failing tests for stream event types**

```swift
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
        {"event_type": "step.start", "index": 0, "step_type": "model_output"}
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
        let json = """{"event_type": "step.stop", "index": 0}""".data(using: .utf8)!
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
        let json = """{"event_type": "future.unknown", "foo": "bar"}""".data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .unknown = event { } else { XCTFail("Expected .unknown for unrecognised event_type") }
    }

    func testErrorEventDecoding() throws {
        let json = """{"event_type": "error", "message": "Something went wrong"}""".data(using: .utf8)!
        let event = try decoder.decode(InteractionStreamEvent.self, from: json)
        if case .error(let msg) = event {
            XCTAssertEqual(msg, "Something went wrong")
        } else { XCTFail("Expected .error") }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter SSEParserTests
```
Expected: Compile error — types not defined.

- [ ] **Step 3: Implement InteractionStreamDelta**

```swift
// In SwiftGeminiInteractions.swift

public enum InteractionStreamDelta: Sendable {
    case text(String)
    case image(Data)
    case functionCallArguments(delta: String, callId: String)
    case codeExecutionArguments(delta: String, id: String)
    case googleSearchQuery(String)
    case urlContextUrl(String)
    case thoughtSummary(String)
    case annotation(Annotation)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, text, data, delta, id
        case callId = "call_id"
        case query, url, summary
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            self = .image(try container.decode(Data.self, forKey: .data))
        case "function_call_arguments":
            self = .functionCallArguments(
                delta: try container.decode(String.self, forKey: .delta),
                callId: try container.decode(String.self, forKey: .callId)
            )
        case "code_execution_arguments":
            self = .codeExecutionArguments(
                delta: try container.decode(String.self, forKey: .delta),
                id: try container.decode(String.self, forKey: .id)
            )
        case "google_search_query":
            self = .googleSearchQuery(try container.decode(String.self, forKey: .query))
        case "url_context_url":
            self = .urlContextUrl(try container.decode(String.self, forKey: .url))
        case "thought_summary":
            self = .thoughtSummary(try container.decode(String.self, forKey: .summary))
        case "annotation":
            self = .annotation(try Annotation(from: decoder))
        default:
            self = .unknown
        }
    }
}
```

- [ ] **Step 4: Implement InteractionStreamEvent**

```swift
public enum InteractionStreamEvent: Codable, Sendable {
    case interactionCreated(Interaction)
    case interactionStatusUpdate(InteractionStatus)
    case stepStart(stepType: String, index: Int)
    case stepDelta(InteractionStreamDelta, stepIndex: Int)
    case stepStop(index: Int)
    case interactionCompleted(Interaction)
    case error(String)
    case unknown   // forward-compatible: silently dropped by stream consumers

    private enum CodingKeys: String, CodingKey {
        case eventType   = "event_type"
        case interaction, status, index, delta, message
        case stepType    = "step_type"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventType = try container.decode(String.self, forKey: .eventType)
        switch eventType {
        case "interaction.created":
            self = .interactionCreated(try container.decode(Interaction.self, forKey: .interaction))
        case "interaction.status_update":
            self = .interactionStatusUpdate(try container.decode(InteractionStatus.self, forKey: .status))
        case "step.start":
            self = .stepStart(
                stepType: try container.decode(String.self, forKey: .stepType),
                index: try container.decode(Int.self, forKey: .index)
            )
        case "step.delta":
            let delta = try container.decode(InteractionStreamDeltaWrapper.self, forKey: .delta)
            self = .stepDelta(delta.value, stepIndex: try container.decode(Int.self, forKey: .index))
        case "step.stop":
            self = .stepStop(index: try container.decode(Int.self, forKey: .index))
        case "interaction.completed":
            self = .interactionCompleted(try container.decode(Interaction.self, forKey: .interaction))
        case "error":
            self = .error(try container.decode(String.self, forKey: .message))
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: any Encoder) throws {
        // Encoding not required — events are only received, never sent
    }
}

// Bridge wrapper to make InteractionStreamDelta Decodable inside the keyed container
private struct InteractionStreamDeltaWrapper: Decodable {
    let value: InteractionStreamDelta
    init(from decoder: any Decoder) throws {
        value = try InteractionStreamDelta(from: decoder)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter SSEParserTests
```
Expected: All 8 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add InteractionStreamEvent and InteractionStreamDelta types"
```

---

## Task 17: SSE parser and stream() / resumeStream()

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/SwiftGeminiInteractions.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/SSEParserTests.swift`

- [ ] **Step 1: Write failing SSE byte-stream tests**

Add to `SSEParserTests`:
```swift
func testSSEParserProducesEventsFromByteStream() async throws {
    let sseData = """
    data: {"event_type": "interaction.created", "interaction": {"id": "v1_abc", "object": "interaction", "model": "gemini-3-flash-preview", "status": "in_progress", "created": "2026-05-24T10:00:00Z", "steps": []}}

    data: {"event_type": "step.start", "index": 0, "step_type": "model_output"}

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
        if case .unknown = event { } // drop silently
    }
    XCTAssertEqual(events.filter { if case .unknown = $0 { return false }; return true }.count, 2)
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "SSEParserTests/testSSEParser|SSEParserTests/testStreamMethod|SSEParserTests/testResumeStream"
```
Expected: Compile error.

- [ ] **Step 3: Implement the SSE parser (internal function)**

```swift
// Internal SSE parser — produces InteractionStreamEvent from a raw byte stream
// Each SSE event is one or more "data: <json>\n" lines followed by a blank line.
func parseSSE(from byteStream: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                var buffer = Data()
                let decoder = JSONDecoder()
                for try await chunk in byteStream {
                    buffer.append(chunk)
                    // Split on double-newline (blank line = event separator)
                    while let range = buffer.range(of: Data("\n\n".utf8)) {
                        let eventData = buffer[buffer.startIndex..<range.lowerBound]
                        buffer.removeSubrange(buffer.startIndex...range.upperBound - 1)
                        // Extract JSON from "data: <json>" lines
                        let lines = String(data: eventData, encoding: .utf8)?.components(separatedBy: "\n") ?? []
                        for line in lines {
                            guard line.hasPrefix("data: ") else { continue }
                            let jsonStr = String(line.dropFirst("data: ".count))
                            guard let jsonData = jsonStr.data(using: .utf8) else { continue }
                            let event = try decoder.decode(InteractionStreamEvent.self, from: jsonData)
                            if case .unknown = event { continue }  // forward-compat: drop unknown events
                            continuation.yield(event)
                        }
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 4: Implement stream() and resumeStream() on InteractionsClient**

```swift
// Add inside the InteractionsClient actor body:

public func stream(_ request: InteractionRequest) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                var r = request
                r.stream = true
                let body = try self.encode(r)
                var urlRequest = self.makeRequest(url: self.interactionsURL(), method: "POST", body: body)
                // Remove Content-Type for streaming — let URLSession handle chunked
                let (bytes, response) = try await self.session.bytes(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.finish(throwing: GeminiInteractionsError.httpError(statusCode: 0, body: "No HTTP response"))
                    return
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    continuation.finish(throwing: GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: ""))
                    return
                }
                // Convert AsyncBytes to AsyncThrowingStream<Data, Error> for parseSSE
                let byteStream = AsyncThrowingStream<Data, Error> { byteContinuation in
                    Task {
                        do {
                            var lineBuffer = Data()
                            for try await byte in bytes {
                                lineBuffer.append(byte)
                                if byte == UInt8(ascii: "\n") {
                                    byteContinuation.yield(lineBuffer)
                                    lineBuffer = Data()
                                }
                            }
                            if !lineBuffer.isEmpty { byteContinuation.yield(lineBuffer) }
                            byteContinuation.finish()
                        } catch {
                            byteContinuation.finish(throwing: error)
                        }
                    }
                }
                for try await event in parseSSE(from: byteStream) {
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

public func resumeStream(
    id: String,
    lastEventId: String
) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                var components = URLComponents(url: self.interactionURL(id: id), resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "stream", value: "true"),
                    URLQueryItem(name: "last_event_id", value: lastEventId)
                ]
                let url = components.url!
                let urlRequest = self.makeRequest(url: url, method: "GET")
                let (bytes, response) = try await self.session.bytes(for: urlRequest)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    continuation.finish()
                    return
                }
                let byteStream = AsyncThrowingStream<Data, Error> { bc in
                    Task {
                        var buf = Data()
                        for try await byte in bytes {
                            buf.append(byte)
                            if byte == UInt8(ascii: "\n") { bc.yield(buf); buf = Data() }
                        }
                        if !buf.isEmpty { bc.yield(buf) }
                        bc.finish()
                    }
                }
                for try await event in parseSSE(from: byteStream) {
                    continuation.yield(event)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter SSEParserTests
```
Expected: All 11 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add SSE parser, stream(), and resumeStream() to InteractionsClient"
```

---

## Task 18: ToolSession — types and run()

**Files:**
- Create: `Sources/SwiftGeminiInteractions/ToolSession.swift`
- Create: `Tests/SwiftGeminiInteractionsTests/ToolSessionTests.swift`

- [ ] **Step 1: Write failing ToolSession tests**

```swift
// Tests/SwiftGeminiInteractionsTests/ToolSessionTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class ToolSessionTests: XCTestCase {

    // Sequence of responses returned by MockURLProtocol for multi-turn scenarios.
    // Each call to requestHandler pops the first element.
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

    func testRunCompletesImmediately() async throws {
        setHandlers([("completed", """{"type":"model_output","content":[{"type":"text","text":"Done"}]}""", "v1_1")])
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
        setHandlers([
            // First: requires_action with function_call
            ("requires_action",
             """{"type":"function_call","id":"call-1","name":"echo","arguments":"{\\"msg\\":\\"hello\\"}"}""",
             "v1_1"),
            // Second: completed with output
            ("completed",
             """{"type":"model_output","content":[{"type":"text","text":"echo: hello"}]}""",
             "v1_2")
        ])
        let client = makeTestClient()
        var capturedCallId: String?
        var capturedArgs: String?
        let session = ToolSession(
            client: client,
            tools: [.function(name: "echo", description: "echoes", parameters: .object([:]))],
            handlers: ["echo": { args in
                capturedArgs = args
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
        XCTAssertNotNil(capturedArgs)
    }

    func testRunThrowsWhenMaxIterationsExceeded() async {
        // Always returns requires_action so the loop never terminates naturally.
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
            tools: [.function(name: "noop", description: "does nothing", parameters: .object([:]))],
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
        var sentBody: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            sentBody = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let json = makeInteractionJSON()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = makeTestClient()
        let session = ToolSession(client: client, tools: [], handlers: [:], maxIterations: 5)
        _ = try await session.run(model: "gemini-3-flash-preview", input: [User("Hi")], configParams: [])
        XCTAssertEqual(sentBody?["store"] as? Bool, true)
    }

    func testRunChainsViaPreviousInteractionId() async throws {
        var requestBodies: [[String: Any]] = []
        MockURLProtocol.requestHandler = { request in
            if let body = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] {
                requestBodies.append(body)
            }
            let iteration = requestBodies.count
            let status = iteration == 1 ? "requires_action" : "completed"
            let steps = iteration == 1
                ? """{"type":"function_call","id":"call-1","name":"fn","arguments":"{}"}"""
                : """{"type":"model_output","content":[{"type":"text","text":"done"}]}"""
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
            tools: [.function(name: "fn", description: "d", parameters: .object([:]))],
            handlers: ["fn": { _ in "result" }],
            maxIterations: 5
        )
        _ = try await session.run(model: "gemini-3-flash-preview", input: [User("Go")], configParams: [])
        // Second request should have previous_interaction_id = "v1_1"
        XCTAssertEqual(requestBodies[1]["previous_interaction_id"] as? String, "v1_1")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter ToolSessionTests
```
Expected: Compile error — ToolSession not defined.

- [ ] **Step 3: Create ToolSession.swift with types and run()**

```swift
// Sources/SwiftGeminiInteractions/ToolSession.swift
import Foundation
import SwiftLLMToolMacros

public struct ToolCallLogEntry: Sendable {
    public let name: String
    public let arguments: String
    public let result: String
    public let duration: Duration
}

public struct ToolSessionResult: Sendable {
    public let interaction: Interaction
    public let iterations: Int
    public let log: [ToolCallLogEntry]
    public let iterationUsages: [Usage]

    public var totalUsage: Usage? {
        guard !iterationUsages.isEmpty else { return nil }
        return iterationUsages.reduce(into: iterationUsages[0]) { acc, usage in
            // Sum scalar fields; modality breakdown is from the last usage
            acc = Usage(
                totalInputTokens:   acc.totalInputTokens   + usage.totalInputTokens,
                totalOutputTokens:  acc.totalOutputTokens  + usage.totalOutputTokens,
                totalThoughtTokens: acc.totalThoughtTokens + usage.totalThoughtTokens,
                totalCachedTokens:  acc.totalCachedTokens  + usage.totalCachedTokens,
                totalToolUseTokens: acc.totalToolUseTokens + usage.totalToolUseTokens,
                totalTokens:        acc.totalTokens        + usage.totalTokens,
                inputTokensByModality: usage.inputTokensByModality
            )
        }
    }
}

public enum ToolSessionEvent: Sendable {
    case iterationStarted(Int)
    case llm(InteractionStreamEvent)
    case toolCallStarted(callId: String, name: String, arguments: String)
    case toolCallCompleted(callId: String, name: String, output: String, duration: Duration)
    case usageUpdate(Usage, iteration: Int)
}

public struct ToolSession: Sendable {
    public typealias ToolHandler = @Sendable (String) async throws -> String

    private let client: InteractionsClient
    private let tools: [InteractionTool]
    private let handlers: [String: ToolHandler]
    private let maxIterations: Int

    public init(
        client: InteractionsClient,
        tools: [InteractionTool],
        handlers: [String: ToolHandler],
        maxIterations: Int = 10
    ) {
        self.client = client
        self.tools = tools
        self.handlers = handlers
        self.maxIterations = maxIterations
    }

    public func run(
        model: String,
        input: [Step],
        configParams: [any InteractionConfigParameter]
    ) async throws -> ToolSessionResult {
        var currentInput = input
        var currentPreviousId: String? = nil
        var iterations = 0
        var log: [ToolCallLogEntry] = []
        var iterationUsages: [Usage] = []

        while iterations < maxIterations {
            iterations += 1
            var request = buildRequest(
                model: model,
                input: currentInput,
                previousId: currentPreviousId,
                configParams: configParams
            )

            let interaction = try await client.send(request)
            if let usage = interaction.usage { iterationUsages.append(usage) }

            if interaction.isComplete || interaction.status != .requiresAction {
                return ToolSessionResult(
                    interaction: interaction,
                    iterations: iterations,
                    log: log,
                    iterationUsages: iterationUsages
                )
            }

            // Collect function_call steps in order
            let functionCalls: [(index: Int, id: String, name: String, arguments: String)] = interaction.steps
                .enumerated()
                .compactMap { (idx, step) in
                    if case .functionCall(let id, let name, let args) = step {
                        return (idx, id, name, args)
                    }
                    return nil
                }

            // Execute all handlers in parallel, preserving original index order
            let results: [(index: Int, callId: String, name: String, output: String, duration: Duration)] =
                try await withThrowingTaskGroup(
                    of: (index: Int, callId: String, name: String, output: String, duration: Duration).self
                ) { group in
                    for call in functionCalls {
                        let handler = handlers[call.name]
                        group.addTask {
                            let clock = ContinuousClock()
                            let start = clock.now
                            let output: String
                            if let handler {
                                do {
                                    output = try await handler(call.arguments)
                                } catch {
                                    output = "Error: \(error.localizedDescription)"
                                }
                            } else {
                                output = "Error: No handler registered for tool '\(call.name)'"
                            }
                            return (call.index, call.id, call.name, output, clock.now - start)
                        }
                    }
                    var collected: [(index: Int, callId: String, name: String, output: String, duration: Duration)] = []
                    for try await result in group { collected.append(result) }
                    return collected.sorted { $0.index < $1.index }
                }

            // Accumulate log entries and build function_result steps for next iteration
            let functionResults: [Step] = results.map { result in
                log.append(ToolCallLogEntry(
                    name: result.name,
                    arguments: functionCalls.first(where: { $0.id == result.callId })?.arguments ?? "",
                    result: result.output,
                    duration: result.duration
                ))
                return FunctionOutput(callId: result.callId, result: result.output)
            }

            currentPreviousId = interaction.id
            currentInput = functionResults
        }

        throw GeminiInteractionsError.maxIterationsExceeded(maxIterations)
    }

    // MARK: - Private

    private func buildRequest(
        model: String,
        input: [Step],
        previousId: String?,
        configParams: [any InteractionConfigParameter]
    ) -> InteractionRequest {
        var request = InteractionRequest(input: .steps(input))
        request.model = model
        request.tools = tools.isEmpty ? nil : tools
        request.store = true  // required for previous_interaction_id chaining
        request.previousInteractionId = previousId
        for param in configParams { param.apply(to: &request) }
        // MaxToolCalls does not apply to the request — it is a ToolSession-level limit
        // PreviousInteractionId from configParams is intentionally overridden above;
        // ToolSession manages chaining automatically.
        return request
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter ToolSessionTests
```
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add ToolSession with parallel tool-calling loop and ToolSessionResult"
```

---

## Task 19: ToolSession — stream()

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/ToolSession.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/ToolSessionTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `ToolSessionTests`:
```swift
func testStreamYieldsIterationStartedAndLLMEvents() async throws {
    let ssePayload = """
    data: {"event_type": "step.start", "index": 0, "step_type": "model_output"}

    data: {"event_type": "step.delta", "index": 0, "delta": {"type": "text", "text": "Done"}}

    data: {"event_type": "step.stop", "index": 0}

    data: {"event_type": "interaction.completed", "interaction": {"id": "v1_s", "object": "interaction", "model": "gemini-3-flash-preview", "status": "completed", "created": "2026-05-24T10:00:00Z", "steps": [{"type":"model_output","content":[{"type":"text","text":"Done"}]}]}}

    """.data(using: .utf8)!

    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, ssePayload)
    }
    let client = makeTestClient()
    let session = ToolSession(client: client, tools: [], handlers: [:], maxIterations: 5)
    var events: [ToolSessionEvent] = []
    for try await event in session.stream(model: "gemini-3-flash-preview", input: [User("Hi")], configParams: []) {
        events.append(event)
    }
    // Should start with .iterationStarted(1)
    if case .iterationStarted(let n) = events.first { XCTAssertEqual(n, 1) }
    else { XCTFail("First event should be iterationStarted(1)") }
    // Should contain llm events
    let llmEvents = events.compactMap { if case .llm(let e) = $0 { return e }; return nil }
    XCTAssertFalse(llmEvents.isEmpty)
}

func testStreamYieldsToolCallEvents() async throws {
    var callCount = 0
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        let status = callCount == 1 ? "requires_action" : "completed"
        let steps = callCount == 1
            ? """{"type":"function_call","id":"call-1","name":"echo","arguments":"{\\"msg\\":\\"hi\\"}"}"""
            : """{"type":"model_output","content":[{"type":"text","text":"echo: hi"}]}"""
        // Return non-SSE JSON for the non-streaming first request
        // and SSE for the streaming second request. In practice, stream() always uses stream=true.
        // We simulate by always returning the non-streaming body — the SSE parser handles empty lines gracefully.
        let json = """
        {"id":"v1_\(callCount)","object":"interaction","model":"gemini-3-flash-preview",
         "status":"\(status)","created":"2026-05-24T10:00:00Z","steps":[\(steps)]}
        """.data(using: .utf8)!
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, json)
    }
    let client = makeTestClient()
    let session = ToolSession(
        client: client,
        tools: [.function(name: "echo", description: "echoes", parameters: .object([:]))],
        handlers: ["echo": { args in
            let d = try JSONDecoder().decode([String: String].self, from: args.data(using: .utf8)!)
            return "echo: \(d["msg"] ?? "")"
        }],
        maxIterations: 5
    )
    var toolStarted = false
    var toolCompleted = false
    for try await event in session.stream(model: "gemini-3-flash-preview", input: [User("Hi")], configParams: []) {
        if case .toolCallStarted = event { toolStarted = true }
        if case .toolCallCompleted(_, _, let output, _) = event {
            toolCompleted = true
            XCTAssertEqual(output, "echo: hi")
        }
    }
    XCTAssertTrue(toolStarted)
    XCTAssertTrue(toolCompleted)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter "ToolSessionTests/testStreamYields"
```
Expected: Compile error — stream() not defined.

- [ ] **Step 3: Implement ToolSession.stream()**

```swift
// Add to ToolSession struct:

public func stream(
    model: String,
    input: [Step],
    configParams: [any InteractionConfigParameter]
) -> AsyncThrowingStream<ToolSessionEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                var currentInput = input
                var currentPreviousId: String? = nil
                var iteration = 0

                while iteration < maxIterations {
                    iteration += 1
                    continuation.yield(.iterationStarted(iteration))

                    let request = buildRequest(
                        model: model,
                        input: currentInput,
                        previousId: currentPreviousId,
                        configParams: configParams
                    )

                    // Collect function calls and final interaction from the SSE stream
                    var functionCalls: [(index: Int, id: String, name: String, arguments: String)] = []
                    var completedInteraction: Interaction? = nil
                    var stepIndex = 0
                    var currentCallId: String? = nil
                    var currentCallName: String? = nil
                    var currentArgBuffer = ""

                    for try await event in client.stream(request) {
                        continuation.yield(.llm(event))
                        switch event {
                        case .stepStart(let stepType, let index):
                            stepIndex = index
                            if stepType == "function_call" {
                                currentArgBuffer = ""
                                currentCallId = nil
                                currentCallName = nil
                            }
                        case .stepDelta(let delta, _):
                            if case .functionCallArguments(let d, let callId) = delta {
                                currentArgBuffer += d
                                currentCallId = callId
                            }
                        case .stepStop:
                            if let callId = currentCallId, let name = currentCallName {
                                functionCalls.append((stepIndex, callId, name, currentArgBuffer))
                            }
                        case .interactionCompleted(let interaction):
                            completedInteraction = interaction
                            if let usage = interaction.usage {
                                continuation.yield(.usageUpdate(usage, iteration: iteration))
                            }
                        default:
                            break
                        }
                    }

                    guard let interaction = completedInteraction else { break }

                    // If no function calls or terminal status, we're done
                    if functionCalls.isEmpty || interaction.isComplete {
                        continuation.finish()
                        return
                    }

                    // Execute tools in parallel
                    let results: [(index: Int, callId: String, name: String, output: String, duration: Duration)] =
                        try await withThrowingTaskGroup(
                            of: (index: Int, callId: String, name: String, output: String, duration: Duration).self
                        ) { group in
                            for call in functionCalls {
                                let handler = handlers[call.name]
                                group.addTask {
                                    continuation.yield(.toolCallStarted(callId: call.id, name: call.name, arguments: call.arguments))
                                    let clock = ContinuousClock()
                                    let start = clock.now
                                    let output: String
                                    if let handler {
                                        do { output = try await handler(call.arguments) }
                                        catch { output = "Error: \(error.localizedDescription)" }
                                    } else {
                                        output = "Error: No handler for '\(call.name)'"
                                    }
                                    let duration = clock.now - start
                                    continuation.yield(.toolCallCompleted(callId: call.id, name: call.name, output: output, duration: duration))
                                    return (call.index, call.id, call.name, output, duration)
                                }
                            }
                            var collected: [(index: Int, callId: String, name: String, output: String, duration: Duration)] = []
                            for try await r in group { collected.append(r) }
                            return collected.sorted { $0.index < $1.index }
                        }

                    let functionResults = results.map { FunctionOutput(callId: $0.callId, result: $0.output) }
                    currentPreviousId = interaction.id
                    currentInput = functionResults
                }

                throw GeminiInteractionsError.maxIterationsExceeded(maxIterations)
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter "ToolSessionTests/testStreamYields"
```
Expected: Both tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add ToolSession.stream() with parallel tool execution and event forwarding"
```

---

## Task 20: Agent actor — AgentTool, TranscriptEntry, send()

**Files:**
- Create: `Sources/SwiftGeminiInteractions/Agent.swift`
- Create: `Tests/SwiftGeminiInteractionsTests/AgentTests.swift`

- [ ] **Step 1: Write failing Agent tests**

```swift
// Tests/SwiftGeminiInteractionsTests/AgentTests.swift
import XCTest
@testable import SwiftGeminiInteractions

final class AgentTests: XCTestCase {

    func testAgentSendWithNoToolsReturnsOutputText() async throws {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON(id: "v1_a1", status: "completed"))
        }
        let client = makeTestClient()
        let agent = try Agent(client: client, model: "gemini-3-flash-preview")
        let reply = try await agent.send("Hello")
        XCTAssertEqual(reply, "Hello!")  // makeInteractionJSON returns "Hello!" in model_output
        let transcript = await agent.transcript
        XCTAssertEqual(transcript.count, 2)  // userMessage + assistantMessage
        if case .userMessage(let msg) = transcript[0] { XCTAssertEqual(msg, "Hello") }
        else { XCTFail("First transcript entry should be userMessage") }
        if case .assistantMessage(let msg) = transcript[1] { XCTAssertEqual(msg, "Hello!") }
        else { XCTFail("Second transcript entry should be assistantMessage") }
    }

    func testAgentChainsViaLastInteractionId() async throws {
        var requestBodies: [[String: Any]] = []
        MockURLProtocol.requestHandler = { request in
            if let body = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] {
                requestBodies.append(body)
            }
            let n = requestBodies.count
            let json = makeInteractionJSON(id: "v1_\(n)")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let client = makeTestClient()
        let agent = try Agent(client: client, model: "gemini-3-flash-preview")
        _ = try await agent.send("First")
        _ = try await agent.send("Second")
        // Second request should include previous_interaction_id = "v1_1"
        XCTAssertEqual(requestBodies[1]["previous_interaction_id"] as? String, "v1_1")
        XCTAssertEqual(requestBodies[1]["store"] as? Bool, true)
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
        let schema = JSONSchemaValue.object([:])
        XCTAssertThrowsError(
            try Agent(client: client, model: "gemini-3-flash-preview") {
                AgentTool(tool: .function(name: "fn", description: "d", parameters: schema), handler: { _ in "ok" })
                AgentTool(tool: .function(name: "fn", description: "d2", parameters: schema), handler: { _ in "ok2" })
            }
        )
    }

    func testAgentNamedAgentInitSetsAgentField() async throws {
        var sentBody: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            sentBody = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON())
        }
        let client = makeTestClient()
        let agent = try Agent(client: client, agent: "deep-research-pro-preview-04-2026")
        _ = try await agent.send("Research quantum computing")
        XCTAssertEqual(sentBody?["agent"] as? String, "deep-research-pro-preview-04-2026")
        XCTAssertNil(sentBody?["model"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter AgentTests
```
Expected: Compile error — Agent, AgentTool not defined.

- [ ] **Step 3: Create Agent.swift with AgentTool, TranscriptEntry, and Agent**

```swift
// Sources/SwiftGeminiInteractions/Agent.swift
import Foundation
import SwiftLLMToolMacros

public struct AgentTool: Sendable {
    public let tool: InteractionTool
    public let handler: ToolSession.ToolHandler

    public init(tool: InteractionTool, handler: @escaping ToolSession.ToolHandler) {
        self.tool = tool
        self.handler = handler
    }

    public init<T: LLMTool>(_ instance: T, strict: Bool? = nil) {
        self.tool = InteractionTool(instance.toolDefinition)
        self.handler = { args in
            guard let data = args.data(using: .utf8) else {
                throw GeminiInteractionsError.invalidInput("Cannot decode tool arguments as UTF-8")
            }
            let arguments = try JSONDecoder().decode(T.Arguments.self, from: data)
            let output = try await instance.call(arguments: arguments)
            return output.content
        }
    }
}

public enum TranscriptEntry: Sendable {
    case userMessage(String)
    case assistantMessage(String)
    case thought(String)
    case toolCall(name: String, arguments: String)
    case toolResult(name: String, result: String, duration: Duration)
    case builtInToolCall(type: String)
    case error(String)
}

// Identifies whether the agent uses a model or a named agent.
private enum ModelIdentifier: Sendable {
    case model(String)
    case agent(String)
}

public actor Agent: Sendable {
    private let client: InteractionsClient
    private let modelIdentifier: ModelIdentifier
    private let instructions: String?
    private let agentTools: [AgentTool]
    private let configParams: [any InteractionConfigParameter]
    private let maxToolIterations: Int

    private var _lastInteractionId: String?
    private var _lastUsage: Usage?
    private var _transcript: [TranscriptEntry] = []

    public var lastInteractionId: String? { _lastInteractionId }
    public var lastUsage: Usage? { _lastUsage }
    public var transcript: [TranscriptEntry] { _transcript }
    public var registeredToolNames: [String] { agentTools.map { toolName($0.tool) }.compactMap { $0 } }

    // Model-based initializer
    public init(
        client: InteractionsClient,
        model: String,
        instructions: String? = nil,
        maxToolIterations: Int = 10,
        @InteractionConfigBuilder config: () -> [any InteractionConfigParameter] = { [] },
        @AgentToolBuilder tools: () -> [AgentTool] = { [] }
    ) throws {
        self.client = client
        self.modelIdentifier = .model(model)
        self.instructions = instructions
        self.maxToolIterations = maxToolIterations
        self.configParams = config()
        let builtTools = tools()
        try Self.validateToolNames(builtTools)
        self.agentTools = builtTools
    }

    // Named-agent initializer
    public init(
        client: InteractionsClient,
        agent: String,
        instructions: String? = nil,
        maxToolIterations: Int = 10,
        @InteractionConfigBuilder config: () -> [any InteractionConfigParameter] = { [] },
        @AgentToolBuilder tools: () -> [AgentTool] = { [] }
    ) throws {
        self.client = client
        self.modelIdentifier = .agent(agent)
        self.instructions = instructions
        self.maxToolIterations = maxToolIterations
        self.configParams = config()
        let builtTools = tools()
        try Self.validateToolNames(builtTools)
        self.agentTools = builtTools
    }

    public func send(_ message: String) async throws -> String {
        _transcript.append(.userMessage(message))
        let interaction: Interaction
        if agentTools.isEmpty {
            interaction = try await sendDirect(message: message)
        } else {
            interaction = try await sendWithTools(message: message)
        }
        _lastInteractionId = interaction.id
        _lastUsage = interaction.usage
        let output = interaction.outputText ?? ""
        appendStepsToTranscript(interaction.steps)
        _transcript.append(.assistantMessage(output))
        return output
    }

    public func stream(_ message: String) -> AsyncThrowingStream<ToolSessionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    _transcript.append(.userMessage(message))
                    if agentTools.isEmpty {
                        // No tools: wrap InteractionsClient.stream() in ToolSessionEvent.llm
                        let request = buildDirectRequest(message: message)
                        var lastInteraction: Interaction? = nil
                        for try await event in client.stream(request) {
                            continuation.yield(.llm(event))
                            if case .interactionCompleted(let i) = event {
                                lastInteraction = i
                                if let usage = i.usage {
                                    continuation.yield(.usageUpdate(usage, iteration: 1))
                                }
                            }
                        }
                        if let interaction = lastInteraction {
                            updateAfterInteraction(interaction)
                        }
                    } else {
                        // Tools: delegate to ToolSession.stream()
                        let session = makeToolSession()
                        let input = buildInputSteps(message: message)
                        for try await event in session.stream(
                            model: modelString(),
                            input: input,
                            configParams: buildConfigParams()
                        ) {
                            continuation.yield(event)
                            recordStreamEvent(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    _transcript.append(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func reset() {
        _lastInteractionId = nil
        _lastUsage = nil
        _transcript = []
    }

    // MARK: - Private helpers

    private func sendDirect(message: String) async throws -> Interaction {
        let request = buildDirectRequest(message: message)
        return try await client.send(request)
    }

    private func sendWithTools(message: String) async throws -> Interaction {
        let session = makeToolSession()
        let input = buildInputSteps(message: message)
        let result = try await session.run(
            model: modelString(),
            input: input,
            configParams: buildConfigParams()
        )
        // Append tool log to transcript
        for entry in result.log {
            _transcript.append(.toolCall(name: entry.name, arguments: entry.arguments))
            _transcript.append(.toolResult(name: entry.name, result: entry.result, duration: entry.duration))
        }
        return result.interaction
    }

    private func buildDirectRequest(message: String) -> InteractionRequest {
        var request = InteractionRequest(input: buildInteractionInput(message: message))
        applyModelIdentifier(to: &request)
        request.systemInstruction = instructions
        if _lastInteractionId != nil { request.store = true }
        request.previousInteractionId = _lastInteractionId
        for param in configParams { param.apply(to: &request) }
        return request
    }

    private func buildInputSteps(message: String) -> [Step] {
        [User(message)]
    }

    private func buildInteractionInput(message: String) -> InteractionInput {
        .text(message)
    }

    private func buildConfigParams() -> [any InteractionConfigParameter] {
        var params = configParams
        if let id = _lastInteractionId {
            params.append(PreviousInteractionId(id))
        }
        if let instr = instructions {
            params.append(SystemInstruction(instr))
        }
        return params
    }

    private func makeToolSession() -> ToolSession {
        var handlers: [String: ToolSession.ToolHandler] = [:]
        for tool in agentTools {
            if let name = toolName(tool.tool) {
                handlers[name] = tool.handler
            }
        }
        return ToolSession(
            client: client,
            tools: agentTools.map { $0.tool },
            handlers: handlers,
            maxIterations: maxToolIterations
        )
    }

    private func applyModelIdentifier(to request: inout InteractionRequest) {
        switch modelIdentifier {
        case .model(let m): request.model = m
        case .agent(let a): request.agent = a
        }
    }

    private func modelString() -> String {
        switch modelIdentifier {
        case .model(let m): return m
        case .agent(let a): return a  // ToolSession uses model: param; agent path uses buildDirectRequest
        }
    }

    private func toolName(_ tool: InteractionTool) -> String? {
        if case .function(let name, _, _) = tool { return name }
        return nil
    }

    private func appendStepsToTranscript(_ steps: [Step]) {
        for step in steps {
            switch step {
            case .thought(let content, let summary):
                let text = summary ?? content.compactMap { if case .text(let t, _) = $0 { return t }; return nil }.joined()
                if !text.isEmpty { _transcript.append(.thought(text)) }
            case .googleSearchCall, .urlContextCall, .codeExecutionCall, .fileSearchCall, .googleMapsCall, .mcpToolCall:
                _transcript.append(.builtInToolCall(type: stepTypeName(step)))
            default:
                break
            }
        }
    }

    private func stepTypeName(_ step: Step) -> String {
        switch step {
        case .googleSearchCall:   return "google_search"
        case .urlContextCall:     return "url_context"
        case .codeExecutionCall:  return "code_execution"
        case .fileSearchCall:     return "file_search"
        case .googleMapsCall:     return "google_maps"
        case .mcpToolCall:        return "mcp_server"
        default:                  return "unknown"
        }
    }

    private func updateAfterInteraction(_ interaction: Interaction) {
        _lastInteractionId = interaction.id
        _lastUsage = interaction.usage
        appendStepsToTranscript(interaction.steps)
    }

    private func recordStreamEvent(_ event: ToolSessionEvent) {
        switch event {
        case .toolCallStarted(_, let name, let args):
            _transcript.append(.toolCall(name: name, arguments: args))
        case .toolCallCompleted(_, let name, let result, let duration):
            _transcript.append(.toolResult(name: name, result: result, duration: duration))
        default:
            break
        }
    }

    private static func validateToolNames(_ tools: [AgentTool]) throws {
        var seen = Set<String>()
        for tool in tools {
            if case .function(let name, _, _) = tool.tool {
                if !seen.insert(name).inserted {
                    throw GeminiInteractionsError.invalidInput("Duplicate tool name: '\(name)'")
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter AgentTests
```
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: add Agent actor with AgentTool, TranscriptEntry, send(), stream(), reset()"
```

---

## Task 21: Full test suite and integration test scaffold

**Files:**
- Create: `Tests/SwiftGeminiInteractionsTests/IntegrationTests.swift`

- [ ] **Step 1: Run full test suite**

```bash
swift test
```
Expected: All tests pass, zero failures.

- [ ] **Step 2: Create integration test scaffold**

```swift
// Tests/SwiftGeminiInteractionsTests/IntegrationTests.swift
import XCTest
@testable import SwiftGeminiInteractions

/// Live API tests. Only run when GEMINI_API_KEY is set in the environment.
final class IntegrationTests: XCTestCase {

    private var apiKey: String?
    private var client: InteractionsClient?

    override func setUp() {
        super.setUp()
        apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
        if let key = apiKey {
            client = InteractionsClient(apiKey: key)
        }
    }

    private func skipIfNoKey() throws {
        try XCTSkipIf(apiKey == nil, "GEMINI_API_KEY not set — skipping integration test")
    }

    func testLiveSendRoundTrip() async throws {
        try skipIfNoKey()
        var request = InteractionRequest(input: .text("Reply with exactly the word: PONG"))
        request.model = "gemini-3-flash-preview"
        let interaction = try await client!.send(request)
        XCTAssertEqual(interaction.status, .completed)
        XCTAssertNotNil(interaction.outputText)
    }

    func testLiveStreamAccumulatesText() async throws {
        try skipIfNoKey()
        var request = InteractionRequest(input: .text("Count from 1 to 5, one number per line."))
        request.model = "gemini-3-flash-preview"
        var accumulated = ""
        for try await event in client!.stream(request) {
            if case .stepDelta(let delta, _) = event, case .text(let t) = delta {
                accumulated += t
            }
        }
        XCTAssertFalse(accumulated.isEmpty)
    }

    func testLiveToolCallingLoop() async throws {
        try skipIfNoKey()
        let schema = JSONSchemaValue.object(["city": .string(nil, nil)])
        let session = ToolSession(
            client: client!,
            tools: [.function(name: "getWeather", description: "Returns weather for a city", parameters: schema)],
            handlers: ["getWeather": { args in
                return "{\"temperature\": 22, \"condition\": \"sunny\"}"
            }],
            maxIterations: 5
        )
        let result = try await session.run(
            model: "gemini-3-flash-preview",
            input: [User("What's the weather in Paris?")],
            configParams: []
        )
        XCTAssertEqual(result.interaction.status, .completed)
        XCTAssertFalse(result.log.isEmpty)
    }

    func testLivePollBackgroundInteraction() async throws {
        try skipIfNoKey()
        var request = InteractionRequest(input: .text("Summarize the concept of recursion in two sentences."))
        request.model = "gemini-3-flash-preview"
        request.background = true
        request.store = true
        let initial = try await client!.send(request)
        // Background interactions start in_progress; poll until done
        let final = try await client!.poll(
            id: initial.id,
            timeout: .seconds(60),
            interval: .seconds(2)
        )
        XCTAssertTrue(final.isComplete)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Tests/
git commit -m "test: add integration test scaffold (skipped without GEMINI_API_KEY)"
```

---

## Task 22: Spec files

**Files:**
- Create: `Spec/what-core.md`
- Create: `Spec/what-toolsession.md`
- Create: `Spec/what-agent.md`
- Create: `Spec/how-client.md`
- Create: `Spec/how-encoding.md`
- Create: `Spec/how-streaming.md`
- Create: `Spec/how-toolloop.md`
- Create: `Spec/how-polling.md`
- Create: `Spec/how-errors.md`

- [ ] **Step 1: Create Spec/ directory and write WHAT specs**

```bash
mkdir -p Spec
```

`Spec/what-core.md` — List every public type in `SwiftGeminiInteractions.swift` with its conformances and public properties. Cover: InteractionStatus, ServiceTier, ResponseModality, ThinkingLevel, ThinkingSummaries, ToolChoiceMode, ToolChoiceConfig, ModalityTokens, Usage, Annotation, Content, Step, GoogleSearchResult, FileSearchResult, InteractionTool, InteractionInput, GenerationConfig, InteractionRequest, ResponseFormat, ResponseDelivery, AudioOutputMimeType, EnvironmentConfig, EnvironmentSource, EnvironmentNetwork, NetworkAllowlistEntry, WebhookConfig, Interaction, GeminiInteractionsError, all InteractionConfigParameter types, all result builders, InteractionsClient, InteractionStreamDelta, InteractionStreamEvent.

`Spec/what-toolsession.md` — Cover: ToolCallLogEntry, ToolSessionResult, ToolSessionEvent, ToolSession.

`Spec/what-agent.md` — Cover: AgentTool, TranscriptEntry, Agent.

- [ ] **Step 2: Write HOW specs**

`Spec/how-client.md` — Document: base URL construction, required headers (x-goog-api-key, Api-Revision, Content-Type), HTTP status code handling (2xx success, 429 rate limit, other errors), timeout configuration via RequestTimeout param, internal URLSession injection for testing.

`Spec/how-encoding.md` — Document: discriminated union encoding strategy (always write `type` key first), CodingKeys snake_case mapping, how InteractionInput encodes as either a bare string or an array, how EnvironmentNetwork encodes as either "disabled" string or an object with allowlist.

`Spec/how-streaming.md` — Document: SSE line accumulation algorithm (split on `\n\n`, extract `data:` prefix, decode JSON, dispatch by `event_type`), unknown event type drop behavior, byte-line accumulation strategy for URLSession.bytes, stream resumption via GET with query params.

`Spec/how-toolloop.md` — Document: `store: true` forced by ToolSession, `previous_interaction_id` threading across iterations, parallel handler execution via withThrowingTaskGroup, result re-sort by original step index, error capture as string (handler failures do not throw out of the loop), maxIterations enforcement.

`Spec/how-polling.md` — Document: ContinuousClock for timeout measurement, terminal statuses (completed, failed, cancelled, incomplete, budgetExceeded), interval sleep between polls, pollTimeout error.

`Spec/how-errors.md` — Document: no Foundation errors escape the public API, URLError → networkError, HTTP non-2xx → httpError, 429 → rateLimitExceeded, DecodingError → decodingError, EncodingError → encodingError, tool handler exceptions → toolExecutionFailed (do not propagate — captured as error strings in tool loop), @unchecked Sendable rationale.

- [ ] **Step 3: Commit**

```bash
git add Spec/
git commit -m "docs: add WHAT and HOW spec files"
```

---

## Task 23: CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: Write CLAUDE.md**

```markdown
# SwiftGeminiInteractions — Architecture Notes

## Key Design Decisions

### Steps-Based Conversation Model
The Interactions API uses a unified `steps` array for both sent and received content — unlike the separate InputItem/OutputItem split in SwiftOpenResponsesDSL. A single `Step` enum with 17 cases handles all roles. Custom `Codable` discriminates on the `"type"` key.

### previous_interaction_id Chaining
`ToolSession` sets `store: true` automatically and threads `previousInteractionId` across iterations. The `PreviousInteractionId` config parameter must NOT be set manually when using ToolSession or Agent — both manage it automatically.

### Built-in Tools vs Function Tools
`InteractionTool` is a single enum. `.function` cases are backed by local `ToolHandler` closures in `ToolSession`/`AgentTool`. Built-in cases (`.googleSearch`, `.codeExecution`, etc.) declare the tool for the API but execute server-side — no handler is registered.

### Agent: Model vs Named Agent
`Agent` has two initializers: `model:` for standard Gemini model strings and `agent:` for named Gemini agents like `deep-research-pro-preview-04-2026`. The `ModelIdentifier` private enum carries this distinction. When using `agent:`, ToolSession is not used — Agent builds requests directly.

### SSE Parsing
Events are separated by blank lines. Each `data: <json>` line is decoded by `event_type`. Unknown event types produce `.unknown` which consumers silently drop for forward compatibility.

### Error Wrapping
No Foundation errors escape the public API. Every catch site wraps into `GeminiInteractionsError`. The enum uses `@unchecked Sendable` because `DecodingError`, `EncodingError`, and `any Error` in `toolExecutionFailed` are not natively Sendable.

### API Revision Header
`Api-Revision: 2026-05-20` is sent on every request. Configurable at `InteractionsClient` init time.

### Testing Strategy
`MockURLProtocol` intercepts `URLSession` at the protocol level. `InteractionsClient` has an internal init that accepts a `URLSession` configured with `MockURLProtocol`. This allows full HTTP-level testing without network access.

## File Map

| File | Contents |
|------|----------|
| `SwiftGeminiInteractions.swift` | All core types, config params, result builders, InteractionsClient, SSE parser |
| `ToolSession.swift` | ToolSession, ToolSessionResult, ToolCallLogEntry, ToolSessionEvent |
| `Agent.swift` | Agent, AgentTool, TranscriptEntry |

## Spec Files

All spec files in `Spec/` must be consulted together during code generation. WHAT specs define the public API surface; HOW specs describe implementation approach (no code).

| Spec | Purpose |
|------|---------|
| `what-core.md` | Types in SwiftGeminiInteractions.swift |
| `what-toolsession.md` | Types in ToolSession.swift |
| `what-agent.md` | Types in Agent.swift |
| `how-client.md` | HTTP construction, headers, error wrapping |
| `how-encoding.md` | Discriminated union encoding strategy |
| `how-streaming.md` | SSE parsing, event dispatch, stream resumption |
| `how-toolloop.md` | Tool loop algorithm, chaining, parallel execution |
| `how-polling.md` | Background poll algorithm |
| `how-errors.md` | Error wrapping strategy |
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md with architecture notes and file map"
```

---

## Task 24: README.md and LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE-2.0.txt` (copy from sibling packages)

- [ ] **Step 1: Copy the Apache 2.0 license**

```bash
cp ../LICENSE-2.0.txt .
```

- [ ] **Step 2: Write README.md**

The README must include: overview, SPM installation, three quick-start code samples (simple send, streaming, agent with tools), section on built-in tools, section on background interactions, and a link to the full API documentation.

Structure:
```markdown
# SwiftGeminiInteractions

Swift package for communicating with Gemini models using the Gemini Interactions API.

## Installation

Add to `Package.swift`:
...(.package(url:, branch:))...

## Quick Start

### Simple interaction
let client = InteractionsClient(apiKey: "YOUR_KEY")
var request = InteractionRequest(input: .text("Hello!"))
request.model = "gemini-3-flash-preview"
let interaction = try await client.send(request)
print(interaction.outputText ?? "")

### Streaming
for try await event in client.stream(request) {
    if case .stepDelta(let delta, _) = event,
       case .text(let text) = delta {
        print(text, terminator: "")
    }
}

### Agent with tools
@LLMTool
struct WeatherTool { ... }

let agent = try Agent(client: client, model: "gemini-3-flash-preview") {
    AgentTool(WeatherTool())
}
let reply = try await agent.send("What's the weather in Tokyo?")

## Built-in Tools
...

## Background Interactions
...
```

- [ ] **Step 3: Commit**

```bash
git add README.md LICENSE-2.0.txt
git commit -m "docs: add README and Apache 2.0 license"
```

---

## Task 25: Examples and guide docs

**Files:**
- Create: `Examples/BasicInteraction.swift`
- Create: `Examples/StreamingInteraction.swift`
- Create: `Examples/ToolSessionExample.swift`
- Create: `Examples/AgentConversation.swift`
- Create: `Examples/BackgroundPolling.swift`
- Create: `docs/background-interactions.md`
- Create: `docs/built-in-tools.md`
- Create: `docs/structured-output.md`

- [ ] **Step 1: Create Examples/ directory and write examples**

Each example is a standalone `@main` struct that demonstrates one feature. They are not compiled by the package (not in Sources/) — they are documentation artifacts.

`Examples/BasicInteraction.swift`:
```swift
import SwiftGeminiInteractions

@main struct BasicInteraction {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
        var request = InteractionRequest(input: .text("What is the capital of France?"))
        request.model = "gemini-3-flash-preview"
        let interaction = try await client.send(request)
        print(interaction.outputText ?? "(no output)")
        print("Tokens used: \(interaction.usage?.totalTokens ?? 0)")
    }
}
```

`Examples/StreamingInteraction.swift`:
```swift
import SwiftGeminiInteractions

@main struct StreamingInteraction {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
        var request = InteractionRequest(input: .text("Tell me a short story about a robot."))
        request.model = "gemini-3-flash-preview"
        for try await event in client.stream(request) {
            switch event {
            case .stepDelta(let delta, _):
                if case .text(let text) = delta { print(text, terminator: "") }
            case .interactionCompleted(let interaction):
                print("\n\nTokens: \(interaction.usage?.totalTokens ?? 0)")
            default: break
            }
        }
    }
}
```

`Examples/ToolSessionExample.swift`:
```swift
import SwiftGeminiInteractions
import SwiftLLMToolMacros

@LLMTool("calculator", "Performs arithmetic on two numbers")
struct Calculator {
    struct Arguments: Decodable {
        let operation: String   // "add", "subtract", "multiply", "divide"
        let a: Double
        let b: Double
    }
    func call(arguments: Arguments) async throws -> ToolOutput {
        switch arguments.operation {
        case "add":      return .init("{\"result\": \(arguments.a + arguments.b)}")
        case "subtract": return .init("{\"result\": \(arguments.a - arguments.b)}")
        case "multiply": return .init("{\"result\": \(arguments.a * arguments.b)}")
        case "divide" where arguments.b != 0:
            return .init("{\"result\": \(arguments.a / arguments.b)}")
        default:
            return .init("{\"error\": \"Invalid operation or division by zero\"}")
        }
    }
}

@main struct ToolSessionExample {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
        let calc = Calculator()
        let session = ToolSession(
            client: client,
            tools: [InteractionTool(calc.toolDefinition)],
            handlers: ["calculator": { args in try await AgentTool(calc).handler(args) }],
            maxIterations: 5
        )
        let result = try await session.run(
            model: "gemini-3-flash-preview",
            input: [User("What is 1234 multiplied by 5678?")],
            configParams: []
        )
        print(result.interaction.outputText ?? "")
        print("Tool calls: \(result.log.count)")
    }
}
```

`Examples/AgentConversation.swift`:
```swift
import SwiftGeminiInteractions
import SwiftLLMToolMacros

@main struct AgentConversation {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
        let agent = try Agent(client: client, model: "gemini-3-flash-preview") {
            Temperature(0.7)
            SystemInstruction("You are a helpful Swift programming tutor.")
        }
        let r1 = try await agent.send("What is a Swift actor?")
        print("Agent: \(r1)\n")
        let r2 = try await agent.send("Can you show me an example?")
        print("Agent: \(r2)\n")
        print("Transcript entries: \(await agent.transcript.count)")
    }
}
```

`Examples/BackgroundPolling.swift`:
```swift
import SwiftGeminiInteractions

@main struct BackgroundPolling {
    static func main() async throws {
        let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
        var request = InteractionRequest(input: .text("Write a comprehensive essay on climate change."))
        request.model = "gemini-3-flash-preview"
        request.background = true
        request.store = true
        let initial = try await client.send(request)
        print("Started background interaction: \(initial.id), status: \(initial.status.rawValue)")
        let completed = try await client.poll(id: initial.id, timeout: .seconds(120), interval: .seconds(3))
        print("Completed: \(completed.outputText?.prefix(200) ?? "(no output)")")
    }
}
```

- [ ] **Step 2: Write guide docs**

`docs/background-interactions.md` — Explain: background: true + store: true required, poll() helper, terminal statuses, recommended timeout/interval values, webhook_config as alternative.

`docs/built-in-tools.md` — Show each built-in tool enum case with a code example. Explain that built-in tools execute server-side — no handler is registered. Show how to combine built-in tools with function tools.

`docs/structured-output.md` — Show ResponseFormat.text with JSON schema, ResponseFormat.image with delivery options, ResponseModalitiesParam usage.

- [ ] **Step 3: Commit**

```bash
git add Examples/ docs/
git commit -m "docs: add examples and guide docs for background, built-in tools, structured output"
```

---

## Phase 2 complete

Run the full test suite one final time:

```bash
swift test
```
Expected: All tests pass, zero failures.

The package is now complete with:
- ✅ SSE streaming (`stream()`, `resumeStream()`, `InteractionStreamEvent`, `InteractionStreamDelta`)
- ✅ `ToolSession` with parallel tool-calling loop, `previous_interaction_id` chaining, streaming variant
- ✅ `Agent` actor with model and named-agent initializers, transcript, `send()`, `stream()`, `reset()`
- ✅ Integration test scaffold (skipped without `GEMINI_API_KEY`)
- ✅ All 9 Spec files (what-*.md and how-*.md)
- ✅ `CLAUDE.md` with architecture notes
- ✅ `README.md` with quick-start samples
- ✅ 5 runnable Examples
- ✅ 3 guide docs
