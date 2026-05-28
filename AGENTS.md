# SwiftGeminiInteractions — AI Coding Reference

Machine-readable documentation for AI coding tools (Claude Code, Copilot, Cursor, etc.).

## Project Overview

SwiftGeminiInteractions is a Swift package for the Google Gemini Interactions API. It supports streaming, multi-turn conversations, tool calling, and autonomous agents.

**Package:** SwiftGeminiInteractions  
**Platforms:** macOS 13+, iOS 16+  
**Swift:** 6.3+  
**Default Trait:** Full (enables all features)

### Source File Structure

| File | Trait gate | Contents |
|------|------------|----------|
| Core.swift | always | All types, config params, result builders, InteractionsClient (send/get/delete/cancel) |
| Streaming.swift | always | SSE parser, stream(), resumeStream(), InteractionStreamEvent, InteractionStreamDelta |
| BackgroundPolling.swift | always | poll() |
| ToolSession.swift | `#if ToolSession` | ToolSession, ToolSessionResult, ToolCallLogEntry, ToolSessionEvent |
| Agent.swift | `#if Agent` | Agent, AgentTool, AgentToolBuilder, TranscriptEntry |

### Trait System

Two traits gate optional orchestration subsystems:

| Trait | Auto-enables | Purpose |
|-------|--------------|---------|
| `ToolSession` | — | Tool-calling loop with automatic chaining |
| `Agent` | `ToolSession` | Stateful agent with transcript and config builders |

The `Full` trait (default) enables both. Consumers who declare `traits: []` get only Core + Streaming + BackgroundPolling.

## Basic Request

### Pattern

```swift
import SwiftGeminiInteractions

let client = InteractionsClient(apiKey: "YOUR_API_KEY")

var request = InteractionRequest(input: .text("What is the capital of France?"))
request.model = "gemini-2.5-flash-preview-05-20"

let interaction = try await client.send(request)

if let text = interaction.outputText {
    print(text)
}
```

### Pitfalls

- **client is an actor** — Methods must be called with `await`. Accessing properties requires actor isolation.
- **model is set separately** — `model` is not part of the `InteractionRequest` initializer; it must be assigned after creation.
- **outputText can be nil** — Check for nil before using. Use `interaction.steps` directly if you need full control.

## Streaming

### Pattern

```swift
let client = InteractionsClient(apiKey: "YOUR_API_KEY")

var request = InteractionRequest(input: .text("Tell me a story"))
request.model = "gemini-2.5-flash-preview-05-20"

for try await event in client.stream(request) {
    switch event {
    case .stepDelta(let delta):
        if case .text(let text) = delta {
            print(text, terminator: "")
        }
    case .interactionComplete(let interaction):
        print("\n\nInteraction ID: \(interaction.id)")
    case .unknown:
        // Forward compatibility: ignore unknown events
        break
    default:
        break
    }
}
```

**Stream Resumption:**

```swift
// Resume from last event
for try await event in client.resumeStream(
    interactionId: "v1_abc123",
    lastEventId: "evt_42"
) {
    // Process events
}
```

### Pitfalls

- **auto-sets stream/store** — `stream()` automatically sets `stream: true` and `store: true` on the request. Don't set these manually.
- **handle .unknown gracefully** — The API may send new event types. Always handle `.unknown` without throwing to maintain forward compatibility.
- **resumeStream needs both IDs** — Both `interactionId` and `lastEventId` are required to resume. The `lastEventId` is provided in each `InteractionStreamEvent`.

## Tools (ToolSession)

### Pattern

```swift
import SwiftGeminiInteractions

// 1. Define a tool using @LLMTool
@LLMTool
struct WeatherTool {
    static let description = "Get current weather for a city"
    
    struct Arguments: Codable {
        let city: String
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        // Fetch weather data
        let temp = 72
        return ToolOutput(content: "The temperature in \(arguments.city) is \(temp)°F")
    }
}

// 2. Create a ToolSession
let client = InteractionsClient(apiKey: "YOUR_API_KEY")
let weatherInstance = WeatherTool()

let session = ToolSession(
    client: client,
    tools: [InteractionTool(WeatherTool.toolDefinition)],
    handlers: [
        "WeatherTool": { args in
            let decoder = JSONDecoder()
            let arguments = try decoder.decode(WeatherTool.Arguments.self, from: Data(args.utf8))
            let output = try await weatherInstance.call(arguments: arguments)
            return output.content
        }
    ],
    maxIterations: 10
)

// 3. Run the session
let result = try await session.run(
    model: "gemini-2.5-flash-preview-05-20",
    input: [.userInput([.text("What's the weather in Paris?")])],
    configParams: []
)

print(result.interaction.outputText ?? "")
print("Iterations: \(result.iterations)")
print("Tool calls: \(result.log.count)")
```

**Streaming variant:**

```swift
for try await event in session.runStreaming(
    model: "gemini-2.5-flash-preview-05-20",
    input: [.userInput([.text("What's the weather in Paris?")])],
    configParams: []
) {
    switch event {
    case .iterationStarted(let n):
        print("Starting iteration \(n)")
    case .llm(.stepDelta(.text(let text))):
        print(text, terminator: "")
    case .toolCallStarted(let callId, let name, let args):
        print("\nCalling tool: \(name)")
    case .toolCallCompleted(let callId, let name, let output, let duration):
        print("Tool \(name) returned: \(output)")
    default:
        break
    }
}
```

### Pitfalls

- **ToolSession manages previousInteractionId/store automatically** — Never set `PreviousInteractionId(...)` or `Store(false)` in `configParams` when using `ToolSession`. The session handles chaining internally.
- **handlers receive raw JSON string** — The handler closure receives a `String` containing JSON. You must parse it manually into your tool's `Arguments` type.
- **built-in tools don't need handlers** — `.googleSearch`, `.codeExecution`, `.urlContext`, `.fileSearch`, `.googleMaps` execute server-side. Only register handlers for `.function` tools.
- **tool calls executed concurrently** — If the model requests multiple tool calls in one turn, `ToolSession` executes them in parallel using `async let`. Ensure your handlers are thread-safe.

## Agent

### Pattern

```swift
import SwiftGeminiInteractions

// 1. Define tools
@LLMTool
struct Calculator {
    static let description = "Perform arithmetic calculations"
    
    struct Arguments: Codable {
        let expression: String
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        // Evaluate expression
        return ToolOutput(content: "Result: 42")
    }
}

// 2. Create an Agent with result builders
let client = InteractionsClient(apiKey: "YOUR_API_KEY")
let calculator = Calculator()

let agent = try Agent(
    client: client,
    model: "gemini-2.5-flash-preview-05-20",
    instructions: "You are a helpful math assistant.",
    maxToolIterations: 10
) {
    // Tools builder
    AgentTool(calculator)
} config: {
    // Config builder
    Temperature(0.7)
    MaxOutputTokens(1024)
}

// 3. Send messages
let response1 = try await agent.send("What is 6 times 7?")
print(response1)

let response2 = try await agent.send("Now add 10 to that result")
print(response2)

// 4. Inspect state
let transcript = await agent.transcript
for entry in transcript {
    switch entry {
    case .userMessage(let msg):
        print("User: \(msg)")
    case .assistantMessage(let msg):
        print("Assistant: \(msg)")
    case .toolCall(let name, let args):
        print("Tool call: \(name)(\(args))")
    case .toolResult(let name, let result, let duration):
        print("Tool result: \(result)")
    default:
        break
    }
}

// 5. Reset conversation
await agent.reset()
```

**Named Agent Pattern:**

```swift
// For named agents (not model strings)
let agent = try Agent(
    client: client,
    agent: "my-production-agent",
    maxToolIterations: 5
) {
    AgentTool(calculator)
} config: {
    Temperature(0.5)
}
```

### Pitfalls

- **manages previousInteractionId/store/systemInstruction automatically** — Never set `PreviousInteractionId(...)`, `Store(...)`, or `SystemInstruction(...)` in the config builder. Agent manages these internally.
- **is an actor** — All properties and methods require `await`. Access `agent.transcript`, `agent.lastUsage`, etc. with `await`.
- **duplicate tool names throw** — If you register multiple tools with the same name, `Agent.init` throws `GeminiInteractionsError.invalidInput`. Use unique names.
- **use AgentTool(instance) over manual init** — The convenience initializer `AgentTool(_ instance: T)` automatically creates both the tool definition and handler. Manual `AgentTool(tool:handler:)` is only needed for custom patterns.
- **reset() clears chain+transcript** — Calling `agent.reset()` discards `lastInteractionId` and the transcript. Use it to start a fresh conversation.
- **use agent: init for named agents** — If you're using a named agent (not a model string), call `Agent(client:agent:...)` instead of `Agent(client:model:...)`.

## Configuration

### Pattern

**Direct apply:**

```swift
var request = InteractionRequest(input: .text("Hello"))
request.model = "gemini-2.5-flash-preview-05-20"

Temperature(0.7).apply(to: &request)
MaxOutputTokens(2048).apply(to: &request)
TopP(0.95).apply(to: &request)

let interaction = try await client.send(request)
```

**Result builder (Agent):**

```swift
let agent = try Agent(
    client: client,
    model: "gemini-2.5-flash-preview-05-20"
) {
    // tools
} config: {
    Temperature(0.9)
    MaxOutputTokens(4096)
    TopP(0.95)
    TopK(40)
    ResponseModalities([.text, .image])
    ServiceTier(.flex)
}
```

### All 17 Configuration Parameters

**Generation Parameters:**
- `Temperature(Double)` — 0.0 to 2.0, controls randomness
- `MaxOutputTokens(Int)` — Maximum tokens to generate
- `TopP(Double)` — 0.0 to 1.0, nucleus sampling threshold
- `TopK(Int)` — Top-k sampling parameter
- `PresencePenalty(Double)` — Penalty for token presence
- `FrequencyPenalty(Double)` — Penalty for token frequency

**Response Configuration:**
- `ResponseModalities([ResponseModality])` — e.g., `[.text, .image]`
- `ResponseMimeType(String)` — e.g., `"application/json"`
- `ResponseSchema(JSONSchemaValue)` — Structured output schema
- `ServiceTier(ServiceTier)` — `.flex`, `.standard`, `.priority`

**Thinking Configuration:**
- `ThinkingLevel(ThinkingLevel)` — `.none`, `.low`, `.medium`, `.high`
- `ThinkingSummaries(ThinkingSummaries)` — `.enabled`, `.disabled`

**Tool Configuration:**
- `ToolChoice(ToolChoiceConfig)` — Control tool selection behavior

**Request Configuration:**
- `MaxToolCalls(Int)` — Maximum tool calls per turn
- `Store(Bool)` — Store interaction for chaining
- `Background(Bool)` — Run in background mode

**Multi-turn Configuration:**
- `PreviousInteractionId(String)` — Chain to previous interaction
- `SystemInstruction(String)` — System prompt

### Structured Output

```swift
let schema = JSONSchemaValue.object(
    properties: [
        ("name", .string(description: "Person's name", enumValues: nil)),
        ("age", .integer(description: "Person's age in years"))
    ],
    required: ["name", "age"]
)

var request = InteractionRequest(input: .text("Extract person info: John is 30 years old"))
request.model = "gemini-2.5-flash-preview-05-20"
ResponseMimeType("application/json").apply(to: &request)
ResponseSchema(schema).apply(to: &request)

let interaction = try await client.send(request)
```

### Pitfalls

- **out-of-range values silently ignored** — If you set `Temperature(5.0)` (out of 0.0–2.0 range), the API may ignore it or clamp it. Always use valid ranges.
- **don't mix direct generationConfig setting with config params** — Never set `request.generationConfig = ...` directly and also use `Temperature(...).apply(to:)`. Choose one approach.

## Background Interactions

### Pattern

```swift
let client = InteractionsClient(apiKey: "YOUR_API_KEY")

var request = InteractionRequest(input: .text("Process this in the background"))
request.model = "gemini-2.5-flash-preview-05-20"
request.background = true
request.store = true

let interaction = try await client.send(request)
print("Interaction ID: \(interaction.id)")
print("Status: \(interaction.status)")

// Poll until completion
do {
    let completed = try await client.poll(
        interactionId: interaction.id,
        interval: .seconds(2),
        timeout: .seconds(60)
    )
    print("Final output: \(completed.outputText ?? "")")
} catch GeminiInteractionsError.pollTimeout(let id) {
    print("Polling timed out for \(id)")
}
```

**Retrieve, cancel, delete:**

```swift
// Get interaction by ID
let retrieved = try await client.get(interactionId: "v1_abc123")

// Cancel running interaction
let cancelled = try await client.cancel(interactionId: "v1_abc123")

// Delete interaction
try await client.delete(interactionId: "v1_abc123")
```

### Pitfalls

- **both background and store required** — Background interactions require both `background: true` and `store: true`. Missing either flag will fail.
- **poll throws .pollTimeout** — If the interaction doesn't complete within the specified timeout, `poll()` throws `GeminiInteractionsError.pollTimeout(id:)`. Handle this case.
- **get/cancel/delete methods** — All three methods exist on `InteractionsClient` and accept an `interactionId: String` parameter.

## Testing

### Pattern

**Complete MockURLProtocol:**

```swift
import Foundation
@testable import SwiftGeminiInteractions

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeTestClient(apiKey: String = "test-key", apiRevision: String = "2026-05-20") -> InteractionsClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return InteractionsClient(apiKey: apiKey, apiRevision: apiRevision, session: session)
}
```

**Test example:**

```swift
import XCTest
@testable import SwiftGeminiInteractions

final class MyTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
    }
    
    func testBasicRequest() async throws {
        let client = makeTestClient()
        
        MockURLProtocol.requestHandler = { request in
            let url = URL(string: "https://generativelanguage.googleapis.com/v1alpha/interactions")!
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let json = """
            {
                "id": "v1_test",
                "object": "interaction",
                "model": "gemini-2.5-flash-preview-05-20",
                "status": "completed",
                "created": "2026-05-24T10:00:00Z",
                "steps": [
                    {"type": "model_output", "content": [{"type": "text", "text": "Hello!"}]}
                ]
            }
            """.data(using: .utf8)!
            return (response, json)
        }
        
        var request = InteractionRequest(input: .text("Hi"))
        request.model = "gemini-2.5-flash-preview-05-20"
        
        let interaction = try await client.send(request)
        XCTAssertEqual(interaction.outputText, "Hello!")
    }
}
```

### Pitfalls

- **test client uses internal init** — `makeTestClient()` uses `InteractionsClient(apiKey:apiRevision:session:)`, which is internal. You must add `@testable import SwiftGeminiInteractions` to your test file.
- **reset handler in tearDown** — Always set `MockURLProtocol.requestHandler = nil` in `tearDown()` to prevent test pollution.
- **integration tests need env vars** — Live integration tests require `GEMINI_API_KEY` environment variable and `RUN_INTEGRATION_TESTS=1` to run. Without these, integration tests are skipped.

## Common Mistakes

1. **Setting PreviousInteractionId with Agent/ToolSession**  
   Agent and ToolSession manage `previousInteractionId` chaining automatically. Never set `PreviousInteractionId(...)` in their config parameters. This causes duplicate chaining or breaks the conversation flow.

2. **Forgetting store:true for manual multi-turn**  
   When chaining interactions manually (not using Agent/ToolSession), you must set both `store: true` and `PreviousInteractionId(...)`. Without `store: true`, the API won't persist the interaction for chaining.

3. **Registering handlers for built-in tools**  
   Built-in tools (`.googleSearch`, `.codeExecution`, `.urlContext`, `.fileSearch`, `.googleMaps`) execute server-side. Don't register handlers for them in `ToolSession` — only register handlers for `.function` tools.

4. **Using #if Agent without enabling trait**  
   Code inside `#if Agent` blocks is only compiled when the Agent trait is enabled. If you depend on Agent types but declare `traits: []` in Package.swift, you'll get compile errors. Use the `Full` trait (default) or explicitly enable `Agent`.

5. **Wrapping GeminiInteractionsError**  
   `GeminiInteractionsError` already wraps all underlying errors (network, decoding, etc.). Don't catch `GeminiInteractionsError` and re-wrap it in your own error type — just propagate it or handle its cases directly.

6. **Mixing direct generationConfig with config params**  
   Don't set `request.generationConfig = GenerationConfig(temperature: 0.7)` and also call `Temperature(0.7).apply(to: &request)`. This creates conflicting state. Use config parameters exclusively.

7. **Not handling .unknown in stream events**  
   The Interactions API may introduce new event types in the future. Always include a `.unknown` case in your `InteractionStreamEvent` switch statements and handle it gracefully (e.g., log and continue). Don't throw on unknown events.
