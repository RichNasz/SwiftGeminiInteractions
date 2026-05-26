---
status: alpha
---

# SwiftGeminiInteractions — Design Spec

**Date:** 2026-05-24  
**Status:** Approved  
**API:** Gemini Interactions API (`https://generativelanguage.googleapis.com/v1beta/interactions`)

---

## Overview

SwiftGeminiInteractions is a Swift package that lets developers communicate with Gemini models and agents using the Gemini Interactions API. It follows the structural and stylistic conventions of SwiftOpenResponsesDSL — result builders, a protocol-driven configuration system, a parallel tool-calling loop, and a stateful `Agent` actor — while preserving all Gemini-specific capabilities without compromise.

The Interactions API differs meaningfully from the Generate API (used by `SwiftGemini`): it uses a Steps-based conversation model, chains turns via `previous_interaction_id`, supports background execution, built-in tools as first-class declarations, named agents (deep-research, etc.), richer content types (image, document, video), and a distinct SSE event schema.

---

## Scope

**Included:**
- Create / get / delete / cancel interactions
- Streaming (SSE) and stream resumption via `last_event_id`
- Custom function tools with `@LLMTool` macro support
- Built-in tools: `google_search`, `code_execution`, `url_context`, `file_search`, `google_maps`, `mcp_server`
- Multi-turn conversations via `previous_interaction_id`
- Background interactions with a `poll()` helper
- Named agent interactions (`agent:` field instead of `model:`)
- Structured output (`response_format`)
- Response modalities (text, image, audio, document)
- `ToolSession` tool-calling loop (parallel execution, `previous_interaction_id` chaining)
- `Agent` actor for stateful conversations
- Webhook config as a passthrough field (URL only — no receiver implementation)
- Environment config for code execution

**Excluded from initial version:**
- OAuth / `SwiftGoogleAuth` dependency (API key only)
- Webhooks as a receiver (HMAC verification, HTTP server)
- Custom Agents CRUD (`/agents` endpoints)
- Computer Use tool
- Audio-native / video-native modalities as primary output targets

---

## Package Structure

```
SwiftGeminiInteractions/
├── Package.swift
├── CLAUDE.md
├── README.md
├── LICENSE-2.0.txt
├── Sources/
│   └── SwiftGeminiInteractions/
│       ├── SwiftGeminiInteractions.swift   ← core types, config, client, streaming
│       ├── ToolSession.swift               ← tool-calling loop, ToolSessionEvent
│       └── Agent.swift                     ← Agent actor, AgentTool, TranscriptEntry
├── Tests/
│   └── SwiftGeminiInteractionsTests/
│       ├── EncodingTests.swift
│       ├── DecodingTests.swift
│       ├── ConfigTests.swift
│       ├── SSEParserTests.swift
│       ├── ToolSessionTests.swift
│       ├── AgentTests.swift
│       └── IntegrationTests.swift
├── Examples/
│   ├── BasicInteraction.swift
│   ├── StreamingInteraction.swift
│   ├── ToolSession.swift
│   ├── AgentConversation.swift
│   └── BackgroundPolling.swift
├── Spec/
│   ├── what-core.md
│   ├── what-toolsession.md
│   ├── what-agent.md
│   ├── how-client.md
│   ├── how-encoding.md
│   ├── how-streaming.md
│   ├── how-toolloop.md
│   ├── how-polling.md
│   └── how-errors.md
├── docs/
│   ├── background-interactions.md
│   ├── built-in-tools.md
│   ├── structured-output.md
│   └── superpowers/
│       └── specs/
│           └── 2026-05-24-gemini-interactions-design.md
└── skills/
```

### Package.swift

- Swift tools version: 6.3
- Platforms: macOS 13+, iOS 16+
- Single external dependency: `SwiftLLMToolMacros` (GitHub, branch `main`)
- No `SwiftGoogleAuth` dependency

---

## Section 1 — Core Types (`SwiftGeminiInteractions.swift`)

### `Step`

The unified polymorphic type for both input and output. The Interactions API uses a single `steps` array for the full conversation — both what you send and what comes back. Encoded/decoded via a `type` string discriminator.

| Case | `type` field | Direction |
|------|-------------|-----------|
| `userInput(content: [Content])` | `user_input` | sent |
| `modelOutput(content: [Content])` | `model_output` | received |
| `thought(content: [Content], summary: String?)` | `thought` | received |
| `functionCall(id: String, name: String, arguments: [String: JSONSchemaValue])` | `function_call` | received |
| `functionResult(callId: String, result: String, name: String?, isError: Bool?)` | `function_result` | sent |
| `codeExecutionCall(id: String, code: String)` | `code_execution_call` | received |
| `codeExecutionResult(callId: String, output: String, isError: Bool?)` | `code_execution_result` | sent/received |
| `googleSearchCall(id: String)` | `google_search_call` | received |
| `googleSearchResult(callId: String, results: [GoogleSearchResult])` | `google_search_result` | received |
| `urlContextCall(id: String, urls: [String])` | `url_context_call` | received |
| `urlContextResult(callId: String, content: String)` | `url_context_result` | received |
| `mcpToolCall(id: String, name: String, arguments: [String: JSONSchemaValue])` | `mcp_server_tool_call` | received |
| `mcpToolResult(callId: String, result: String)` | `mcp_server_tool_result` | received |
| `fileSearchCall(id: String)` | `file_search_call` | received |
| `fileSearchResult(callId: String, results: [FileSearchResult])` | `file_search_result` | received |
| `googleMapsCall(id: String)` | `google_maps_call` | received |
| `googleMapsResult(callId: String, result: String)` | `google_maps_result` | received |

`Step` conforms to `Codable` and `Sendable`. Custom `encode(to:)` and `init(from:)` probe for the `type` key first, then decode the appropriate payload. Unknown `type` values produce a decoding error.

### `Content`

Content lives inside a step's `content` array. Discriminated by `type`.

```
text(String, annotations: [Annotation]?)     → type: "text"
image(data: Data?, mimeType: String?, uri: String?)     → type: "image"
document(data: Data?, mimeType: String?, uri: String?)  → type: "document"
video(data: Data?, mimeType: String?, uri: String?)     → type: "video"
```

`data` is base64-encoded in JSON. Either `data` or `uri` is present, not both.

### `Annotation`

Inline citation attached to text content.

```
urlCitation(url: String, title: String?, startIndex: Int, endIndex: Int)
fileCitation(documentUri: String, fileName: String, source: String,
             pageNumber: Int?, startIndex: Int, endIndex: Int)
placeCitation(name: String, startIndex: Int, endIndex: Int)
```

### `InteractionTool`

Declared in the request `tools` array. Built-in tools are enum cases with no handler — they run server-side. Custom function tools are backed by local handlers in `ToolSession` and `Agent`.

```
function(name: String, description: String, parameters: JSONSchemaValue)
codeExecution
googleSearch
urlContext
fileSearch(storeNames: [String], topK: Int?, metadataFilter: String?)
googleMaps(latitude: Double, longitude: Double, enableWidget: Bool?)
mcpServer
```

Custom encoding: `.function` encodes `type: "function"` with nested `name`, `description`, `parameters`. Built-in cases encode `type: "<case-name>"` with no additional fields.

`InteractionTool` can be constructed from a `ToolDefinition` produced by the `@LLMTool` macro (from `SwiftLLMToolMacros`):
```swift
public extension InteractionTool {
    init(_ definition: ToolDefinition)
}
```
This initializer maps `definition.name`, `definition.description`, and `definition.parameters` into the `.function` case.

### `Interaction`

The response object returned by every API call.

```swift
public struct Interaction: Codable, Sendable {
    public let id: String
    public let object: String           // always "interaction"
    public let model: String?
    public let agent: String?
    public let status: InteractionStatus
    public let created: String
    public let updated: String?
    public let steps: [Step]
    public let usage: Usage?

    // Convenience
    public var outputText: String?      // text from most recent model_output step
    public var requiresAction: Bool     // status == .requiresAction
    public var functionCalls: [Step]    // all .functionCall cases in steps
    public var isComplete: Bool         // status == .completed || .failed || .cancelled
}
```

### `InteractionStatus`

```swift
public enum InteractionStatus: String, Codable, Sendable {
    case inProgress     = "in_progress"
    case requiresAction = "requires_action"
    case completed      = "completed"
    case failed         = "failed"
    case cancelled      = "cancelled"
    case incomplete     = "incomplete"
    case budgetExceeded = "budget_exceeded"
}
```

### `Usage`

Richer than OpenAI's — includes per-modality token breakdowns.

```swift
public struct Usage: Codable, Sendable {
    public let totalInputTokens: Int
    public let totalOutputTokens: Int
    public let totalThoughtTokens: Int
    public let totalCachedTokens: Int
    public let totalToolUseTokens: Int
    public let totalTokens: Int
    public let inputTokensByModality: [ModalityTokens]
}

public struct ModalityTokens: Codable, Sendable {
    public let modality: String   // "text", "image", "audio", etc.
    public let tokens: Int
}
```

### `InteractionRequest`

```swift
public struct InteractionRequest: Codable, Sendable {
    public var model: String?
    public var agent: String?                       // mutually exclusive with model
    public var input: InteractionInput              // string or [Step]
    public var systemInstruction: String?
    public var tools: [InteractionTool]?
    public var stream: Bool?
    public var store: Bool?
    public var background: Bool?
    public var generationConfig: GenerationConfig?
    public var responseFormat: ResponseFormat?
    public var responseModalities: [ResponseModality]?
    public var previousInteractionId: String?
    public var environment: EnvironmentConfig?
    public var webhookConfig: WebhookConfig?
    public var serviceTier: ServiceTier?
}

public enum InteractionInput: Codable, Sendable {
    case text(String)
    case steps([Step])
}
```

### `GenerationConfig`

```swift
public struct GenerationConfig: Codable, Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var maxOutputTokens: Int?
    public var seed: Int?
    public var stopSequences: [String]?
    public var thinkingLevel: ThinkingLevel?
    public var thinkingSummaries: ThinkingSummaries?
    public var toolChoice: ToolChoiceConfig?
}
```

### Supporting Enums and Types

```swift
public enum ServiceTier: String, Codable, Sendable {
    case flex, standard, priority
}

public enum ResponseModality: String, Codable, Sendable {
    case text, image, audio, video, document
}

public enum ThinkingLevel: String, Codable, Sendable {
    case none, low, medium, high
}

public enum ThinkingSummaries: String, Codable, Sendable {
    case enabled, disabled
}

public struct ToolChoiceConfig: Codable, Sendable {
    public let mode: ToolChoiceMode
    public let allowedTools: [String]?
}

public enum ToolChoiceMode: String, Codable, Sendable {
    case auto, none, required
}

public struct GoogleSearchResult: Codable, Sendable {
    public let title: String?
    public let url: String?
    public let snippet: String?
}

public struct FileSearchResult: Codable, Sendable {
    public let fileId: String?
    public let fileName: String?
    public let snippet: String?
    public let score: Double?
}
```

### `ResponseFormat`

Discriminated by `type`. Supports image and audio delivery in addition to structured text.

```swift
public enum ResponseFormat: Codable, Sendable {
    case text(mimeType: String? = nil, schema: JSONSchemaValue? = nil)
    case image(mimeType: String, aspectRatio: String? = nil,
               imageSize: String? = nil, delivery: ResponseDelivery? = nil)
    case audio(mimeType: AudioOutputMimeType, sampleRate: Int? = nil,
               bitRate: Int? = nil, delivery: ResponseDelivery? = nil)
}

public enum ResponseDelivery: String, Codable, Sendable {
    case inline, uri
}

public enum AudioOutputMimeType: String, Codable, Sendable {
    case mp3   = "audio/mp3"
    case oggOpus = "audio/ogg_opus"
    case l16   = "audio/l16"
    case wav   = "audio/wav"
    case alaw  = "audio/alaw"
    case mulaw = "audio/mulaw"
}
```

### `EnvironmentConfig`

```swift
public struct EnvironmentConfig: Codable, Sendable {
    public let type: String                    // always "remote"
    public let sources: [EnvironmentSource]?
    public let network: EnvironmentNetwork?
}

public enum EnvironmentSource: Codable, Sendable {
    case inline(target: String, content: String)
    case repository(source: String, target: String)
    case gcs(source: String, target: String)
}

public enum EnvironmentNetwork: Codable, Sendable {
    case allowlist([NetworkAllowlistEntry])
    case disabled
}

public struct NetworkAllowlistEntry: Codable, Sendable {
    public let domain: String
    public let transform: [String: String]?
}
```

### `WebhookConfig`

Passthrough — developers supply the webhook URI(s); the package does not implement a receiver.

```swift
public struct WebhookConfig: Codable, Sendable {
    public let notificationEndpoints: [String]
    public let userMetadata: [String: String]?
}
```

### `GeminiInteractionsError`

No Foundation errors escape the public API surface.

```swift
public enum GeminiInteractionsError: Error, LocalizedError, Sendable {
    case networkError(URLError)
    case httpError(statusCode: Int, body: String)
    case rateLimitExceeded
    case decodingError(DecodingError)
    case encodingError(EncodingError)
    case invalidInput(String)
    case toolExecutionFailed(name: String, error: Error)
    case maxIterationsExceeded(Int)
    case pollTimeout(id: String)
    case interactionFailed(id: String, status: InteractionStatus)
}
```

### Convenience Input Constructors

```swift
public func User(_ text: String) -> Step
public func User(_ content: [Content]) -> Step
public func FunctionOutput(callId: String, result: String, isError: Bool = false) -> Step
```

---

## Section 2 — Configuration Parameter System

### Protocol

```swift
public protocol InteractionConfigParameter: Sendable {
    func apply(to request: inout InteractionRequest)
}
```

### Parameters

| Type | Validates |
|------|-----------|
| `Temperature(Double)` | 0.0–2.0 |
| `TopP(Double)` | 0.0–1.0 |
| `MaxOutputTokens(Int)` | > 0 |
| `Seed(Int)` | any |
| `SystemInstruction(String)` | non-empty |
| `PreviousInteractionId(String)` | non-empty |
| `Store(Bool)` | — |
| `Background(Bool)` | — |
| `ServiceTierParam(ServiceTier)` | flex / standard / priority |
| `ThinkingLevelParam(ThinkingLevel)` | none / low / medium / high |
| `ThinkingSummariesParam(ThinkingSummaries)` | — |
| `ResponseFormatParam(ResponseFormat)` | — |
| `ResponseModalitiesParam([ResponseModality])` | non-empty |
| `MaxToolCalls(Int)` | > 0 |
| `EnvironmentParam(EnvironmentConfig)` | — |
| `RequestTimeout(TimeInterval)` | 10–900 s |
| `WebhookConfigParam(WebhookConfig)` | — |

### Result Builders

```swift
@resultBuilder public struct InteractionConfigBuilder { ... }
@resultBuilder public struct StepsBuilder { ... }
@resultBuilder public struct ToolsBuilder { ... }
@resultBuilder public struct AgentToolBuilder { ... }
```

---

## Section 3 — `InteractionsClient` Actor

```swift
public actor InteractionsClient {
    public let baseURL: URL   // internal access for extensions

    public init(apiKey: String, apiRevision: String = "2026-05-20")

    // Core operations
    public func send(_ request: InteractionRequest) async throws -> Interaction
    public func stream(_ request: InteractionRequest) -> AsyncThrowingStream<InteractionStreamEvent, Error>
    public func get(id: String) async throws -> Interaction
    public func delete(id: String) async throws
    public func cancel(id: String) async throws

    // Background interactions
    public func poll(
        id: String,
        timeout: Duration = .seconds(300),
        interval: Duration = .seconds(5)
    ) async throws -> Interaction

    // Stream resumption
    public func resumeStream(
        id: String,
        lastEventId: String
    ) -> AsyncThrowingStream<InteractionStreamEvent, Error>
}
```

**Headers sent on every request:**
- `x-goog-api-key: <apiKey>`
- `Api-Revision: <apiRevision>`
- `Content-Type: application/json`

**HTTP strategy:** 200–299 is success. 429 maps to `rateLimitExceeded`. All other non-2xx map to `httpError(statusCode:body:)`. All `Foundation` errors wrap into `GeminiInteractionsError`.

**`poll()` algorithm:** Loop calling `get(id:)` with `ContinuousClock` for timeout measurement. Return immediately on any terminal status (`completed`, `failed`, `cancelled`, `incomplete`, `budgetExceeded`). Sleep `interval` between polls. Throw `pollTimeout` if elapsed time exceeds `timeout`.

---

## Section 4 — Streaming (`InteractionStreamEvent`)

The Interactions API SSE scheme uses `event_type` discriminators with `content.start / content.delta / content.stop` nomenclature — different from OpenAI's scheme.

```swift
public enum InteractionStreamEvent: Sendable {
    case interactionCreated(Interaction)
    case interactionStatusUpdate(InteractionStatus)
    case stepStart(stepType: String, index: Int)
    case stepDelta(InteractionStreamDelta, stepIndex: Int)
    case stepStop(index: Int)
    case interactionCompleted(Interaction)
    case error(String)
}

public enum InteractionStreamDelta: Sendable {
    case text(String)
    case image(Data)
    case functionCallArguments(delta: String, callId: String)
    case codeExecutionArguments(delta: String, id: String)
    case googleSearchQuery(String)
    case urlContextUrl(String)
    case thoughtSummary(String)
    case annotation(Annotation)
}
```

**SSE parsing:** Read `event:` and `data:` lines from the byte stream. Accumulate `data:` content between blank-line separators. Decode `event_type` from the JSON payload, then dispatch to the appropriate `InteractionStreamEvent` case. Unknown event types are silently dropped (forward compatibility).

**Stream resumption:** `resumeStream(id:lastEventId:)` issues a GET to `/{apiRevision}/interactions/{id}?stream=true&last_event_id={lastEventId}` and parses the response body as SSE identically to `stream()`.

---

## Section 5 — Tool-Calling Loop (`ToolSession.swift`)

### Types

```swift
public struct ToolSession: Sendable {
    public typealias ToolHandler = @Sendable (String) async throws -> String

    public init(
        client: InteractionsClient,
        tools: [InteractionTool],
        handlers: [String: ToolHandler],
        maxIterations: Int = 10
    )

    public func run(
        model: String,
        input: [Step],
        configParams: [any InteractionConfigParameter]
    ) async throws -> ToolSessionResult

    public func stream(
        model: String,
        input: [Step],
        configParams: [any InteractionConfigParameter]
    ) -> AsyncThrowingStream<ToolSessionEvent, Error>
}
```

### Loop Algorithm (`run`)

1. Create interaction with `store: true`, `model`, `input`, `tools`, config params applied
2. Collect `usage`; increment iteration counter
3. If `status == .completed` (or other terminal) → return `ToolSessionResult`
4. If `status == .requiresAction` → collect all `.functionCall` steps
5. Execute all handlers in parallel via `withThrowingTaskGroup`:
   - Look up handler by function name
   - Invoke with raw JSON arguments string
   - Time execution with `ContinuousClock`
   - Capture result or format error string
   - Re-sort results by original step index after group completes
6. Build `functionResult` steps from outputs
7. Create new interaction with `previousInteractionId = last.id`, `input = .steps(functionResults)`
8. Repeat from step 2
9. Throw `maxIterationsExceeded(maxIterations)` if limit reached

The `store: true` parameter is set automatically by `ToolSession` — callers do not need to set it. The `PreviousInteractionId` config parameter must not be set manually when using `ToolSession` or `Agent`; both manage it automatically. Setting it manually will conflict with the loop's chaining logic.

### `ToolSessionResult`

```swift
public struct ToolSessionResult: Sendable {
    public let interaction: Interaction
    public let iterations: Int
    public let log: [ToolCallLogEntry]
    public let iterationUsages: [Usage]
    public var totalUsage: Usage?        // summed across iterations
}

public struct ToolCallLogEntry: Sendable {
    public let name: String
    public let arguments: String
    public let result: String
    public let duration: Duration
}
```

### `ToolSessionEvent` (streaming loop)

```swift
public enum ToolSessionEvent: Sendable {
    case iterationStarted(Int)
    case llm(InteractionStreamEvent)
    case toolCallStarted(callId: String, name: String, arguments: String)
    case toolCallCompleted(callId: String, name: String, output: String, duration: Duration)
    case usageUpdate(Usage, iteration: Int)
}
```

**Streaming loop:** Same algorithm as `run` but:
- Yield `.iterationStarted(n)` at the top of each iteration
- Use `client.stream()` instead of `client.send()`, forwarding all `InteractionStreamEvent`s as `.llm(event)`
- Collect function calls from `.stepDelta` / `.stepStop` events
- Yield `.toolCallStarted` before invoking each handler
- Yield `.toolCallCompleted` after each handler finishes
- Yield `.usageUpdate` after the response completes

---

## Section 6 — `Agent` Actor (`Agent.swift`)

```swift
public actor Agent: Sendable {
    // Model-based initializer
    public init(
        client: InteractionsClient,
        model: String,
        instructions: String? = nil,
        maxToolIterations: Int = 10,
        @InteractionConfigBuilder config: () -> [any InteractionConfigParameter] = { [] },
        @AgentToolBuilder tools: () -> [AgentTool] = { [] }
    ) throws

    // Named-agent initializer (e.g. "deep-research-pro-preview-04-2026")
    public init(
        client: InteractionsClient,
        agent: String,
        instructions: String? = nil,
        maxToolIterations: Int = 10,
        @InteractionConfigBuilder config: () -> [any InteractionConfigParameter] = { [] },
        @AgentToolBuilder tools: () -> [AgentTool] = { [] }
    ) throws

    // Read-only state
    public var lastInteractionId: String?
    public var lastUsage: Usage?
    public var transcript: [TranscriptEntry]
    public var registeredToolNames: [String]

    // Conversation
    public func send(_ message: String) async throws -> String
    public func stream(_ message: String) -> AsyncThrowingStream<ToolSessionEvent, Error>
    public func reset()
}
```

**Two initializers** — one for `model:` (standard Gemini model string) and one for `agent:` (named Gemini agent like `deep-research-pro-preview-04-2026`). Both are otherwise identical. Both validate no duplicate tool names and throw `invalidInput` if violated.

**`send(_:)` algorithm:**
1. Append `User(message)` step to transcript
2. If no tools: create a bare interaction; set `store: true` if `lastInteractionId` is non-nil so chaining works for multi-turn conversations without tools
3. If tools: delegate to `ToolSession.run()`, recording tool activity in transcript
4. Update `lastInteractionId`, `lastUsage`
5. Append assistant message (and any `.thought` steps) to transcript; return `outputText`

**Conversation chaining:** Uses `lastInteractionId` as `previousInteractionId` on each subsequent `send()` call. `store: true` is set automatically whenever tools are present or `lastInteractionId` is non-nil.

**`stream(_:)` with no tools:** When the `Agent` has no registered tools, `stream()` wraps the underlying `InteractionsClient.stream()` directly — yielding `.llm(event)` events only. No `.iterationStarted`, `.toolCallStarted`, or `.toolCallCompleted` events are emitted. Usage is still yielded as `.usageUpdate` when the `interactionCompleted` event arrives.

### `AgentTool`

```swift
public struct AgentTool: Sendable {
    public let tool: InteractionTool
    public let handler: ToolSession.ToolHandler

    public init(tool: InteractionTool, handler: @escaping ToolSession.ToolHandler)
    public init<T: LLMTool>(_ instance: T, strict: Bool? = nil)
}
```

The `init<T: LLMTool>` initializer decodes JSON arguments as `T.Arguments`, calls `instance.call(arguments:)`, and returns `output.content` — identical to SwiftOpenResponsesDSL's `AgentTool` initializer.

### `TranscriptEntry`

```swift
public enum TranscriptEntry: Sendable {
    case userMessage(String)
    case assistantMessage(String)
    case thought(String)                           // Gemini-specific: thought steps
    case toolCall(name: String, arguments: String)
    case toolResult(name: String, result: String, duration: Duration)
    case builtInToolCall(type: String)             // Gemini-specific: google_search, code_execution, etc.
    case error(String)
}
```

---

## Section 7 — Testing

### Unit Tests (no network, always run in CI)

| File | What it tests |
|------|--------------|
| `EncodingTests.swift` | JSON encoding of every `Step` variant, `Content` type, `InteractionTool` case, `InteractionRequest`, `ResponseFormat`, `EnvironmentConfig` |
| `DecodingTests.swift` | JSON decoding of `Interaction`, all `Step` variants, `Usage`, `ModalityTokens`, `GeminiInteractionsError` payloads |
| `ConfigTests.swift` | `InteractionConfigParameter` validation (out-of-range temperature, empty strings, invalid timeouts), result builder composition |
| `SSEParserTests.swift` | Feed raw byte sequences into the SSE parser; verify correct `InteractionStreamEvent` sequence, unknown event type drops, stream resumption headers |
| `ToolSessionTests.swift` | Tool loop logic using `MockInteractionsClient` — parallel execution, result ordering, `previousInteractionId` threading, `maxIterations` enforcement, error propagation |
| `AgentTests.swift` | Transcript accumulation, `reset()`, dual initializer (model vs agent), duplicate tool name validation |
| `IntegrationTests.swift` | Skipped unless `GEMINI_API_KEY` is set in environment |

**`MockInteractionsClient`:** A test double with injectable `Interaction` responses and controllable SSE event streams. Exposed as `internal` so all test files can use it without duplicating setup.

### Integration Tests (require `GEMINI_API_KEY`)

- Live `send()` round-trip with a real model
- Live `stream()` with text delta accumulation
- Live tool-calling loop with a simple echo function
- `poll()` for a background interaction with timeout

---

## Section 8 — Open Source Documentation

| Path | Purpose |
|------|---------|
| `README.md` | Overview, SPM installation, quick-start samples (simple send, streaming, agent with tools) |
| `CLAUDE.md` | Architecture notes, key design decisions, file map, spec file index |
| `docs/background-interactions.md` | Guide to background mode and the `poll()` helper |
| `docs/built-in-tools.md` | Guide to declaring and using built-in tools |
| `docs/structured-output.md` | Guide to `ResponseFormat` and `responseModalities` |
| `Examples/` | Five runnable Swift scripts covering main use cases |
| `Spec/` | WHAT specs (public API surface) + HOW specs (implementation approach, no code) |
| `LICENSE-2.0.txt` | Apache 2.0 |

### Spec Files

| File | Purpose |
|------|---------|
| `Spec/what-core.md` | All types in `SwiftGeminiInteractions.swift` |
| `Spec/what-toolsession.md` | Types in `ToolSession.swift` |
| `Spec/what-agent.md` | Types in `Agent.swift` |
| `Spec/how-client.md` | HTTP construction, auth header, `Api-Revision`, error wrapping |
| `Spec/how-encoding.md` | JSON encoding strategy for discriminated unions (`Step`, `Content`, `InteractionTool`, `InteractionStreamEvent`) |
| `Spec/how-streaming.md` | SSE parsing, event dispatch, stream resumption |
| `Spec/how-toolloop.md` | Tool-calling loop algorithm, `previous_interaction_id` chaining, parallel execution |
| `Spec/how-polling.md` | Background interaction poll algorithm with timeout and interval |
| `Spec/how-errors.md` | Error wrapping strategy — no Foundation errors escape the public API |

### Public API Documentation

Every public type, initializer, and method receives a DocC-style `///` doc comment written as part of its implementation task — not as a separate pass.

---

## Key Design Decisions

### Steps over separate Input/Output types
The Interactions API uses a unified `steps` array for both sent and received content. A single `Step` enum handles all cases rather than the separate `InputItem`/`OutputItem` split in SwiftOpenResponsesDSL.

### `previous_interaction_id` chaining
`ToolSession` sets `store: true` automatically and threads `previousInteractionId` across iterations. Callers never manage interaction storage manually.

### Built-in tools as enum cases
Built-in tools (`google_search`, `code_execution`, etc.) are declared as `InteractionTool` enum cases with no associated handler — they run server-side. Only `function` cases are paired with `ToolHandler` closures in `ToolSession` and `AgentTool`.

### Named agent support
`Agent` has two initializers — `model:` for standard Gemini model strings and `agent:` for named Gemini agents like `deep-research-pro-preview-04-2026`. Both paths otherwise behave identically.

### API key only, no OAuth
Authentication is `x-goog-api-key` header only. No `SwiftGoogleAuth` dependency.

### Gemini-specific transcript entries
`TranscriptEntry` adds `.thought` and `.builtInToolCall` cases absent from SwiftOpenResponsesDSL's equivalent — preserving full visibility into Gemini's reasoning steps and server-side tool activity.

### `Api-Revision` header
Sent on every request. Defaults to `"2026-05-20"` (the current revision) but is configurable at `InteractionsClient` init time.
