# Documentation Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace scattered docs with a progressive-disclosure documentation suite: lean README, 7 topic guides, AGENTS.md for AI tools, and DocC comments on all public API.

**Architecture:** Each markdown guide covers one topic and links forward to the next. AGENTS.md is machine-readable with pattern/pitfall sections. DocC comments are inline `///` on all public declarations. Old docs are removed after their content is folded into new guides.

**Tech Stack:** Markdown, Swift DocC comments

**Spec:** `docs/superpowers/specs/2026-05-25-documentation-design.md`

---

## File Structure

**Create:**
- `README.md` (rewrite)
- `docs/getting-started.md`
- `docs/streaming.md`
- `docs/tools.md`
- `docs/agent.md`
- `docs/configuration.md`
- `docs/error-handling.md`
- `docs/background-and-polling.md`
- `docs/traits.md` (minor update)
- `AGENTS.md`

**Remove:**
- `docs/built-in-tools.md`
- `docs/structured-output.md`
- `docs/background-interactions.md`

---

### Task 1: README.md

**Files:**
- Rewrite: `README.md`

- [ ] **Step 1: Rewrite README.md**

Replace the entire contents of `README.md` with:

```markdown
# SwiftGeminiInteractions

A Swift client for the [Gemini Interactions API](https://ai.google.dev/gemini-api/docs/interactions) — send requests, stream responses, call tools, and run multi-turn agents.

## Install

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/RichNasz/SwiftGeminiInteractions.git", branch: "main")
]
```

Then add the product to your target:

```swift
.product(name: "SwiftGeminiInteractions", package: "SwiftGeminiInteractions")
```

## Quick Start

```swift
import SwiftGeminiInteractions

let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)

var request = InteractionRequest(input: .text("What is the capital of France?"))
request.model = "gemini-2.5-flash-preview-05-20"

let interaction = try await client.send(request)
print(interaction.outputText ?? "")
```

## Guides

| Guide | What you'll learn |
|-------|-------------------|
| [Getting Started](docs/getting-started.md) | Client setup, first request, understanding responses |
| [Streaming](docs/streaming.md) | Real-time event streaming, deltas, resumption |
| [Tools](docs/tools.md) | Function calling, @LLMTool macro, built-in tools |
| [Agent](docs/agent.md) | Multi-turn conversations with automatic tool execution |
| [Configuration](docs/configuration.md) | All 17 config parameters, structured output, response formats |
| [Error Handling](docs/error-handling.md) | Every error case, when it fires, recovery patterns |
| [Background & Polling](docs/background-and-polling.md) | Long-running tasks, polling, webhooks |
| [Traits](docs/traits.md) | Selective compilation with Swift Package Traits |

## For AI Coding Tools

See [AGENTS.md](AGENTS.md) for patterns and pitfalls when working with this library programmatically.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE-2.0.txt](LICENSE-2.0.txt).
```

- [ ] **Step 2: Verify the file reads correctly**

Run: `wc -l README.md`
Expected: approximately 50-60 lines

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README as lean landing page with guide links"
```

---

### Task 2: docs/getting-started.md

**Files:**
- Create: `docs/getting-started.md`

- [ ] **Step 1: Write docs/getting-started.md**

```markdown
# Getting Started

This guide walks you through your first request and introduces the core types you'll work with.

## Creating an InteractionsClient

```swift
import SwiftGeminiInteractions

let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
```

The client is an `actor` — safe to share across tasks. It handles authentication, encoding, error wrapping, and HTTP transport.

Optional parameters:
- `apiRevision`: API version header (default: `"2026-05-20"`)

## Your First Request

Build an `InteractionRequest`, set the model, and send it:

```swift
var request = InteractionRequest(input: .text("Explain Swift concurrency in one paragraph."))
request.model = "gemini-2.5-flash-preview-05-20"

let interaction = try await client.send(request)
print(interaction.outputText ?? "No output")
print("Tokens used: \(interaction.usage?.totalTokens ?? 0)")
```

`InteractionInput` has two forms:
- `.text("...")` — a simple text prompt
- `.steps([...])` — an array of `Step` values for multi-turn or tool-calling flows

## Understanding the Response

`client.send()` returns an `Interaction`:

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Unique interaction ID (used for chaining, polling, cancellation) |
| `status` | `InteractionStatus` | `.completed`, `.inProgress`, `.failed`, etc. |
| `steps` | `[Step]` | All input and output steps |
| `outputText` | `String?` | Convenience — extracts the last text from the last `modelOutput` step |
| `usage` | `Usage?` | Token counts (input, output, thought, cached, tool-use) |
| `isComplete` | `Bool` | `true` for terminal statuses |
| `functionCalls` | `[Step]` | Convenience — filters steps to just `.functionCall` cases |

## The Step Enum

`Step` is a discriminated union with 17 cases representing everything that can appear in a conversation:

**Input steps** (you send these):
- `.userInput(content:)` — user message with `[Content]` (text, images, documents, audio, video)
- `.functionResult(callId:result:name:isError:)` — result from a tool call

**Output steps** (the model returns these):
- `.modelOutput(content:)` — model's response content
- `.thought(content:)` — model's thinking (when thinking is enabled)
- `.functionCall(id:name:arguments:)` — model requesting a tool call

**Built-in tool steps:**
- `.googleSearchCall(id:)`, `.googleSearchResult(results:)` — web search
- `.codeExecutionCall(id:code:)`, `.codeExecutionResult(id:output:)` — code execution
- `.urlContextCall(id:)`, `.urlContextResult(id:content:)` — URL reading
- `.fileSearchCall(id:)`, `.fileSearchResult(id:results:)` — file search
- `.mcpToolCall(id:name:arguments:)`, `.mcpToolResult(id:name:result:)` — MCP server

The `User()` convenience function creates `.userInput` steps:

```swift
let step = User("Hello!") // equivalent to Step.userInput(content: [.text(text: "Hello!", annotations: nil)])
```

## Multi-turn Conversations

Chain interactions by passing the previous interaction's ID:

```swift
var request1 = InteractionRequest(input: .text("What is Swift?"))
request1.model = "gemini-2.5-flash-preview-05-20"
request1.store = true  // required for chaining

let interaction1 = try await client.send(request1)

var request2 = InteractionRequest(input: .text("How does it compare to Kotlin?"))
request2.model = "gemini-2.5-flash-preview-05-20"
request2.previousInteractionId = interaction1.id
request2.store = true

let interaction2 = try await client.send(request2)
// interaction2 has full context from interaction1
```

**Important:** `store` must be `true` for the previous interaction to be retrievable. Without it, `previousInteractionId` will fail.

You can also use config parameters for this:

```swift
var request2 = InteractionRequest(input: .text("How does it compare to Kotlin?"))
request2.model = "gemini-2.5-flash-preview-05-20"
PreviousInteractionId(interaction1.id).apply(to: &request2)
Store(true).apply(to: &request2)
```

## What's Next

- [Streaming](streaming.md) — get responses in real time
- [Tools](tools.md) — let the model call your functions
- [Agent](agent.md) — multi-turn conversations with automatic tool execution
- [Configuration](configuration.md) — temperature, thinking, structured output, and more
```

- [ ] **Step 2: Commit**

```bash
git add docs/getting-started.md
git commit -m "docs: add getting-started guide"
```

---

### Task 3: docs/streaming.md

**Files:**
- Create: `docs/streaming.md`

- [ ] **Step 1: Write docs/streaming.md**

```markdown
# Streaming

Stream responses in real time instead of waiting for the complete interaction.

## Basic Streaming

```swift
var request = InteractionRequest(input: .text("Tell me a story."))
request.model = "gemini-2.5-flash-preview-05-20"

for try await event in client.stream(request) {
    switch event {
    case .interactionCreated(let interaction):
        print("Started: \(interaction.id)")
    case .stepDelta(let delta, _):
        if case .text(let text) = delta {
            print(text, terminator: "")
        }
    case .interactionCompleted(let interaction):
        print("\nDone. Tokens: \(interaction.usage?.totalTokens ?? 0)")
    default:
        break
    }
}
```

`client.stream()` returns an `AsyncThrowingStream<InteractionStreamEvent, Error>`. The client automatically sets `stream: true` and `store: true` on the request.

## Event Types

| Event | When it fires |
|-------|---------------|
| `.interactionCreated(Interaction)` | Connection established, interaction ID available |
| `.interactionStatusUpdate(InteractionStatus)` | Status changed (e.g., in-progress) |
| `.stepStart(stepType:index:)` | A new step began (model_output, function_call, etc.) |
| `.stepDelta(InteractionStreamDelta, stepIndex:)` | Incremental content within a step |
| `.stepStop(index:)` | A step finished |
| `.interactionCompleted(Interaction)` | Final event — complete interaction with all steps and usage |
| `.error(String)` | Server-side error message |
| `.unknown` | Unrecognized event type (silently dropped for forward compatibility) |

## Working with Deltas

`InteractionStreamDelta` tells you what kind of content arrived:

| Delta | Content |
|-------|---------|
| `.text(String)` | Text fragment from model output |
| `.image(Data)` | Image data chunk |
| `.functionCallArguments(delta:callId:)` | Partial JSON arguments for a function call |
| `.codeExecutionArguments(delta:id:)` | Partial code for code execution |
| `.googleSearchQuery(String)` | Search query the model is issuing |
| `.urlContextUrl(String)` | URL the model is fetching |
| `.thoughtSummary(String)` | Summary of model thinking |
| `.annotation(Annotation)` | Citation or annotation |
| `.unknown` | Unrecognized delta type |

To accumulate text:

```swift
var fullText = ""
for try await event in client.stream(request) {
    if case .stepDelta(let delta, _) = event,
       case .text(let chunk) = delta {
        fullText += chunk
    }
}
print(fullText)
```

## Resuming Interrupted Streams

If a stream drops mid-response, resume from the last received event:

```swift
let resumed = client.resumeStream(id: interactionId, lastEventId: lastEventId)
for try await event in resumed {
    // continues from where it left off
}
```

Track the `interactionId` from the `.interactionCreated` event and the last event ID you processed. `resumeStream` issues a GET request with `last_event_id` as a query parameter.

## Error Handling in Streams

Errors are delivered in two ways:

1. **`.error(String)` event** — server-side error within the stream (e.g., content safety)
2. **Thrown error** — network failure, HTTP error, or decoding failure wrapped in `GeminiInteractionsError`

```swift
do {
    for try await event in client.stream(request) {
        if case .error(let message) = event {
            print("Server error: \(message)")
        }
        // handle other events...
    }
} catch {
    print("Stream failed: \(error)")
}
```

## What's Next

- [Tools](tools.md) — function calling with streaming support
- [Agent](agent.md) — streaming multi-turn agent conversations
```

- [ ] **Step 2: Commit**

```bash
git add docs/streaming.md
git commit -m "docs: add streaming guide"
```

---

### Task 4: docs/tools.md

**Files:**
- Create: `docs/tools.md`

- [ ] **Step 1: Write docs/tools.md**

```markdown
# Tools

Tools let the model call functions you define or use server-side capabilities like web search and code execution.

## Concepts

There are two kinds of tools:

- **Function tools** — you define the schema and provide a handler. The model generates arguments; your code executes the function and returns results. Requires the `ToolSession` trait.
- **Built-in tools** — server-side capabilities (web search, code execution, etc.) that the model invokes directly. No handler needed. Work with any trait configuration.

Both are represented by the `InteractionTool` enum.

## Built-in Tools

Use built-in tools by adding them to the request's `tools` array:

```swift
var request = InteractionRequest(input: .text("What happened in the Swift 6 release?"))
request.model = "gemini-2.5-flash-preview-05-20"
request.tools = [.googleSearch]
let interaction = try await client.send(request)
```

Available built-in tools:

| Tool | Description |
|------|-------------|
| `.googleSearch` | Web search with grounding |
| `.codeExecution` | Sandboxed code execution |
| `.urlContext` | Fetches and reads URL content |
| `.fileSearch(storeNames:topK:metadataFilter:)` | Searches uploaded file stores |
| `.googleMaps(latitude:longitude:enableWidget:)` | Maps and places queries |
| `.mcpServer` | Routes calls to a configured MCP server |

Results appear as step pairs in the interaction (e.g., `.googleSearchCall` followed by `.googleSearchResult`).

## ToolSession

`ToolSession` runs an automatic tool-calling loop: send → check status → execute function calls → chain results → repeat until the model is done or `maxIterations` is reached.

**Requires the `ToolSession` trait** (enabled by default).

```swift
let schema = JSONSchemaValue.object(
    properties: [
        ("city", .string(description: "City name")),
    ],
    required: ["city"]
)

let session = ToolSession(
    client: client,
    tools: [.function(name: "get_weather", description: "Get weather for a city", parameters: schema)],
    handlers: [
        "get_weather": { arguments in
            // arguments is a JSON string, e.g. {"city":"Tokyo"}
            return "{\"temperature\": 22, \"condition\": \"sunny\"}"
        }
    ],
    maxIterations: 10
)

let result = try await session.run(
    model: "gemini-2.5-flash-preview-05-20",
    input: [User("What's the weather in Tokyo?")],
    configParams: []
)
print(result.interaction.outputText ?? "")
print("Tool calls: \(result.log.count), Iterations: \(result.iterations)")
```

`ToolSession.run()` returns a `ToolSessionResult`:

| Property | Type | Description |
|----------|------|-------------|
| `interaction` | `Interaction` | The final interaction |
| `iterations` | `Int` | Number of LLM round-trips |
| `log` | `[ToolCallLogEntry]` | Every tool call with name, arguments, result, and duration |
| `totalUsage` | `Usage?` | Summed token usage across all iterations |

### How the Loop Works

1. Send the request to the model
2. If the response status is `.requiresAction`, collect all `.functionCall` steps
3. Execute all handlers concurrently via a `TaskGroup`
4. Build `.functionResult` steps from the outputs
5. Send the results as the next input, chaining via `previousInteractionId`
6. Repeat until the model returns a terminal status or `maxIterations` is exceeded

## The @LLMTool Macro

Instead of manually building JSON schemas and writing handler closures, use the `@LLMTool` macro from the `SwiftLLMToolMacros` package (re-exported by SwiftGeminiInteractions):

```swift
import SwiftGeminiInteractions

@LLMTool("get_weather", "Returns current weather for a city")
struct GetWeather {
    struct Arguments: Decodable {
        /// The city to get weather for
        let city: String
    }
    func call(arguments: Arguments) async throws -> ToolOutput {
        // your implementation here
        return ToolOutput("{\"temperature\": 22, \"condition\": \"sunny\"}")
    }
}
```

The macro generates:
- `LLMTool` protocol conformance
- `LLMToolArguments` conformance on `Arguments` with a `jsonSchema` property
- `name`, `description`, and `toolDefinition` static properties

Use it with `ToolSession` via `InteractionTool.init`:

```swift
let tool = InteractionTool(GetWeather.toolDefinition)
```

Or with `Agent` via `AgentTool` (see the [Agent guide](agent.md)):

```swift
AgentTool(GetWeather())
```

## Mixing Tool Types

Combine function tools and built-in tools in the same request:

```swift
let session = ToolSession(
    client: client,
    tools: [
        .googleSearch,
        .function(name: "save_result", description: "Save a search result", parameters: schema)
    ],
    handlers: [
        "save_result": { arguments in
            // only function tools need handlers; built-in tools are server-side
            return "Saved."
        }
    ]
)
```

## Tool Choice

Control which tools the model can use:

```swift
var request = InteractionRequest(input: .text("..."))
request.generationConfig = GenerationConfig(toolChoice: ToolChoiceConfig(mode: .required))
```

| Mode | Behavior |
|------|----------|
| `.auto` | Model decides whether to call tools (default) |
| `.none` | Model cannot call any tools |
| `.required` | Model must call at least one tool |

Restrict to specific tools:

```swift
ToolChoiceConfig(mode: .required, allowedTools: ["get_weather"])
```

## Streaming with Tools

`ToolSession.stream()` yields `ToolSessionEvent` values that include both LLM streaming events and tool execution lifecycle:

```swift
for try await event in session.stream(
    model: "gemini-2.5-flash-preview-05-20",
    input: [User("What's the weather in Tokyo and London?")],
    configParams: []
) {
    switch event {
    case .iterationStarted(let n):
        print("--- Iteration \(n) ---")
    case .llm(let streamEvent):
        if case .stepDelta(let delta, _) = streamEvent,
           case .text(let text) = delta {
            print(text, terminator: "")
        }
    case .toolCallStarted(_, let name, _):
        print("Calling \(name)...")
    case .toolCallCompleted(_, let name, let output, let duration):
        print("\(name) returned in \(duration): \(output)")
    case .usageUpdate(let usage, let iteration):
        print("Iteration \(iteration) tokens: \(usage.totalTokens)")
    }
}
```

## What's Next

- [Agent](agent.md) — a higher-level wrapper that manages tools, chaining, and transcripts automatically
- [Configuration](configuration.md) — temperature, thinking, and other generation settings
```

- [ ] **Step 2: Commit**

```bash
git add docs/tools.md
git commit -m "docs: add tools guide"
```

---

### Task 5: docs/agent.md

**Files:**
- Create: `docs/agent.md`

- [ ] **Step 1: Write docs/agent.md**

```markdown
# Agent

`Agent` is an `actor` that wraps `ToolSession` with automatic interaction chaining, transcript tracking, and usage aggregation. Use it when you want multi-turn conversations where the model can call tools.

**Requires the `Agent` trait** (enabled by default, auto-enables `ToolSession`).

## Creating an Agent

```swift
import SwiftGeminiInteractions

let agent = try Agent(
    client: client,
    model: "gemini-2.5-flash-preview-05-20"
)
```

With tools and configuration:

```swift
@LLMTool("get_weather", "Returns current weather for a city")
struct GetWeather {
    struct Arguments: Decodable { let city: String }
    func call(arguments: Arguments) async throws -> ToolOutput {
        return ToolOutput("{\"temperature\": 22}")
    }
}

let agent = try Agent(
    client: client,
    model: "gemini-2.5-flash-preview-05-20",
    instructions: "You are a helpful weather assistant.",
    maxToolIterations: 5
) {
    AgentTool(GetWeather())
} config: {
    Temperature(0.7)
    MaxOutputTokens(2048)
}
```

The `tools:` closure uses `@AgentToolBuilder` and the `config:` closure uses `@InteractionConfigBuilder` — both are result builders that support conditionals and loops.

## Multi-turn Conversations

`agent.send()` automatically chains interactions via `previousInteractionId` and sets `store: true`:

```swift
let r1 = try await agent.send("What is Swift?")
print(r1)

let r2 = try await agent.send("How does it compare to Kotlin?")
print(r2) // has full context from r1
```

Call `agent.reset()` to clear the chain and start a new conversation:

```swift
agent.reset()
let r3 = try await agent.send("New topic — tell me about Rust.")
```

## AgentTool

`AgentTool` pairs an `InteractionTool` with a handler. Two ways to create one:

**From an @LLMTool type** (recommended):

```swift
AgentTool(GetWeather())
```

This extracts the tool definition and creates a handler that decodes arguments, calls your function, and returns the output.

**Manual init:**

```swift
AgentTool(
    tool: .function(name: "greet", description: "Greet a user", parameters: schema),
    handler: { arguments in
        // arguments is a raw JSON string
        return "Hello!"
    }
)
```

Duplicate tool names throw an error at `Agent.init` time.

## Streaming

`agent.stream()` returns an `AsyncThrowingStream<ToolSessionEvent, Error>`:

```swift
for try await event in agent.stream("What's the weather in Tokyo?") {
    switch event {
    case .llm(let streamEvent):
        if case .stepDelta(let delta, _) = streamEvent,
           case .text(let text) = delta {
            print(text, terminator: "")
        }
    case .toolCallStarted(_, let name, _):
        print("\nCalling \(name)...")
    case .toolCallCompleted(_, let name, let output, _):
        print("\(name) → \(output)")
    default:
        break
    }
}
```

If the agent has no tools, streaming falls through to `client.stream()` directly.

## Transcript

The agent records every interaction in a transcript:

```swift
for entry in agent.transcript {
    switch entry {
    case .userMessage(let msg):    print("User: \(msg)")
    case .assistantMessage(let msg): print("Assistant: \(msg)")
    case .toolCall(let name, _):   print("Tool call: \(name)")
    case .toolResult(let name, let result, let duration):
        print("Tool result: \(name) (\(duration)): \(result)")
    case .thought(let t):          print("Thought: \(t)")
    case .builtInToolCall(let t):  print("Built-in: \(t)")
    case .error(let e):            print("Error: \(e)")
    }
}
```

`agent.reset()` clears the transcript along with the interaction chain.

## Named Agents

Target a named Gemini agent instead of a model string:

```swift
let agent = try Agent(client: client, agent: "my-named-agent")
let reply = try await agent.send("Hello!")
```

The `agent:` initializer sends the `agent` field instead of `model` in the request JSON. When combined with tools, the agent overrides the `model` field that `ToolSession.buildRequest` sets.

## Usage Tracking

After each `send()` or `stream()`, check token usage:

```swift
if let usage = agent.lastUsage {
    print("Input: \(usage.totalInputTokens), Output: \(usage.totalOutputTokens)")
    print("Total: \(usage.totalTokens)")
}
```

For tool-calling flows, `lastUsage` reflects the final iteration's usage. Use `ToolSessionResult.totalUsage` (available via `ToolSession.run()`) for summed usage across all iterations.

## What's Next

- [Configuration](configuration.md) — all 17 config parameters
- [Error Handling](error-handling.md) — handling failures in agent workflows
```

- [ ] **Step 2: Commit**

```bash
git add docs/agent.md
git commit -m "docs: add agent guide"
```

---

### Task 6: docs/configuration.md

**Files:**
- Create: `docs/configuration.md`

- [ ] **Step 1: Write docs/configuration.md**

```markdown
# Configuration

SwiftGeminiInteractions uses config parameter structs to modify requests. Each struct conforms to `InteractionConfigParameter` and has a single `apply(to:)` method.

## Using Config Parameters

Apply directly to a request:

```swift
var request = InteractionRequest(input: .text("Hello"))
request.model = "gemini-2.5-flash-preview-05-20"
Temperature(0.7).apply(to: &request)
MaxOutputTokens(1024).apply(to: &request)
SystemInstruction("You are a pirate.").apply(to: &request)
```

Or use the `@InteractionConfigBuilder` result builder with `Agent`:

```swift
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    // tools...
} config: {
    Temperature(0.7)
    MaxOutputTokens(1024)
    SystemInstruction("You are a pirate.")
    if useThinking {
        ThinkingLevelParam(.high)
    }
}
```

## Parameter Reference

### Generation Config Parameters

These set fields on `InteractionRequest.generationConfig`:

| Parameter | Type | Range | Description |
|-----------|------|-------|-------------|
| `Temperature(Double)` | `Double` | 0.0–2.0 | Sampling temperature. Higher = more creative. |
| `TopP(Double)` | `Double` | 0.0–1.0 | Nucleus sampling threshold |
| `MaxOutputTokens(Int)` | `Int` | 1+ | Maximum tokens in the response |
| `Seed(Int)` | `Int` | any | Deterministic sampling seed |
| `ThinkingLevelParam(ThinkingLevel)` | `.none`, `.low`, `.medium`, `.high` | — | How much the model thinks before responding |
| `ThinkingSummariesParam(ThinkingSummaries)` | `.enabled`, `.disabled` | — | Whether thinking summaries are included |

### Request-Level Parameters

These set fields directly on `InteractionRequest`:

| Parameter | Type | Description |
|-----------|------|-------------|
| `SystemInstruction(String)` | `String` | System prompt |
| `Store(Bool)` | `Bool` | Whether to store the interaction (required for chaining) |
| `Background(Bool)` | `Bool` | Run as a background interaction |
| `PreviousInteractionId(String)` | `String` | Chain to a previous interaction |
| `ServiceTierParam(ServiceTier)` | `.flex`, `.standard`, `.priority` | Processing tier |
| `ResponseFormatParam(ResponseFormat)` | `ResponseFormat` | Output format (JSON schema, image, audio) |
| `ResponseModalitiesParam([ResponseModality])` | `[ResponseModality]` | Output modalities (text, image, audio, etc.) |
| `EnvironmentParam(EnvironmentConfig)` | `EnvironmentConfig` | Sandbox environment for code execution |
| `WebhookConfigParam(WebhookConfig)` | `WebhookConfig` | Webhook notification config |

### No-op Parameters

These carry values but don't modify the request — they're read by `ToolSession` or `Agent`:

| Parameter | Type | Description |
|-----------|------|-------------|
| `MaxToolCalls(Int)` | `Int` | Read by orchestration layers |
| `RequestTimeout(TimeInterval)` | `TimeInterval` | Read by orchestration layers |

Values outside a parameter's range are silently ignored (the `apply` method returns without modifying the request). Empty strings and empty arrays are also ignored.

## Structured Output

Use `ResponseFormat.text` with a JSON schema to constrain the model to return valid JSON:

```swift
let schema = JSONSchemaValue.object(
    properties: [
        ("city", .string(description: "City name")),
        ("country", .string(description: "Country code")),
        ("population", .integer(description: "Population"))
    ],
    required: ["city", "country", "population"]
)

var request = InteractionRequest(input: .text("Facts about Tokyo"))
request.model = "gemini-2.5-flash-preview-05-20"
request.responseFormat = .text(mimeType: "application/json", schema: schema)

let interaction = try await client.send(request)
if let json = interaction.outputText {
    let data = json.data(using: .utf8)!
    let city = try JSONDecoder().decode(CityInfo.self, from: data)
}
```

`JSONSchemaValue` cases:
- `.object(properties:required:)` — object with named properties
- `.array(items:)` — array of a specific type
- `.string(description:enumValues:)` — string, optionally constrained to enum values
- `.integer(description:minimum:maximum:)` — integer with optional bounds
- `.number(description:minimum:maximum:)` — floating-point with optional bounds
- `.boolean(description:)` — boolean
- `.null` — null

## Response Modalities

Request non-text output:

```swift
var request = InteractionRequest(input: .text("Draw a cat"))
request.model = "gemini-2.5-flash-preview-05-20"
request.responseModalities = [.image]
request.responseFormat = .image(mimeType: "image/png", aspectRatio: "1:1", imageSize: nil, delivery: .inline)
```

Audio output:

```swift
request.responseModalities = [.audio]
request.responseFormat = .audio(mimeType: .mp3, sampleRate: 24000, bitRate: 128000, delivery: .inline)
```

`ResponseDelivery`:
- `.inline` — binary data embedded in the response (base64)
- `.uri` — API returns a URI to fetch separately (better for large files)

## Environment Config

Configure sandboxed environments for code execution:

```swift
let env = EnvironmentConfig(
    sources: [.inline(target: "/workspace/main.py", content: "print('hello')")],
    network: .disabled
)
EnvironmentParam(env).apply(to: &request)
```

Network options:
- `.disabled` — no network access
- `.allowlist([NetworkAllowlistEntry])` — only specified domains

## What's Next

- [Error Handling](error-handling.md) — understanding and recovering from errors
- [Background & Polling](background-and-polling.md) — long-running tasks
```

- [ ] **Step 2: Commit**

```bash
git add docs/configuration.md
git commit -m "docs: add configuration guide"
```

---

### Task 7: docs/error-handling.md

**Files:**
- Create: `docs/error-handling.md`

- [ ] **Step 1: Write docs/error-handling.md**

```markdown
# Error Handling

All errors from SwiftGeminiInteractions are wrapped in `GeminiInteractionsError`. No raw Foundation errors escape the public API.

## Error Cases

| Case | When it fires |
|------|---------------|
| `.networkError(URLError)` | Network connectivity failure (no internet, DNS, timeout) |
| `.httpError(statusCode:body:)` | Non-2xx HTTP response from the API |
| `.rateLimitExceeded` | HTTP 429 — too many requests |
| `.decodingError(DecodingError)` | Response JSON could not be decoded |
| `.encodingError(EncodingError)` | Request could not be encoded to JSON |
| `.invalidInput(String)` | Invalid input (e.g., duplicate tool names in Agent) |
| `.toolExecutionFailed(name:error:)` | A tool handler threw an error |
| `.maxIterationsExceeded(Int)` | ToolSession/Agent exceeded max tool-calling iterations |
| `.pollTimeout(id:)` | `client.poll()` exceeded its timeout duration |
| `.interactionFailed(id:status:)` | Interaction reached a non-success terminal status |

## HTTP Errors

```swift
do {
    let interaction = try await client.send(request)
} catch let error as GeminiInteractionsError {
    switch error {
    case .httpError(let statusCode, let body):
        switch statusCode {
        case 400: print("Bad request: \(body)")
        case 401: print("Invalid API key")
        case 403: print("Permission denied")
        case 429: print("Rate limited")
        case 500...599: print("Server error: \(body)")
        default: print("HTTP \(statusCode): \(body)")
        }
    case .rateLimitExceeded:
        print("Rate limited — wait and retry")
    default:
        print(error.localizedDescription)
    }
}
```

## Rate Limiting

`.rateLimitExceeded` is thrown for HTTP 429. Implement exponential backoff:

```swift
func sendWithRetry(_ request: InteractionRequest, maxRetries: Int = 3) async throws -> Interaction {
    for attempt in 0..<maxRetries {
        do {
            return try await client.send(request)
        } catch GeminiInteractionsError.rateLimitExceeded {
            let delay = Double(1 << attempt) // 1s, 2s, 4s
            try await Task.sleep(for: .seconds(delay))
        }
    }
    return try await client.send(request)
}
```

## Tool Errors

When a tool handler throws, `ToolSession` catches the error and sends it back to the model as a `.functionResult` with `isError: true`. The model can then decide how to proceed. The error is **not** re-thrown to your code — the tool loop continues.

If you need to surface a tool failure, throw from within your handler and it will appear in the `ToolCallLogEntry.result` as an error string.

`.maxIterationsExceeded` fires when the model keeps requesting tool calls beyond the configured limit:

```swift
let session = ToolSession(client: client, tools: tools, handlers: handlers, maxIterations: 5)
// If the model calls tools more than 5 times, throws .maxIterationsExceeded(5)
```

## Polling Errors

```swift
do {
    let result = try await client.poll(id: interactionId, timeout: .seconds(60))
} catch GeminiInteractionsError.pollTimeout(let id) {
    print("Interaction \(id) did not complete within 60s")
} catch GeminiInteractionsError.interactionFailed(let id, let status) {
    print("Interaction \(id) failed with status: \(status.rawValue)")
}
```

## All Errors Have Descriptions

Every case has a `localizedDescription` via `LocalizedError`:

```swift
catch let error as GeminiInteractionsError {
    print(error.localizedDescription)
    // "HTTP 400: {\"error\": \"invalid model\"}"
    // "Tool 'get_weather' failed: connection refused"
    // "Exceeded maximum tool iterations (10)."
    // "Poll timed out for interaction 'v1_abc123'."
}
```

## What's Next

- [Background & Polling](background-and-polling.md) — long-running tasks and webhooks
```

- [ ] **Step 2: Commit**

```bash
git add docs/error-handling.md
git commit -m "docs: add error-handling guide"
```

---

### Task 8: docs/background-and-polling.md

**Files:**
- Create: `docs/background-and-polling.md`

- [ ] **Step 1: Write docs/background-and-polling.md**

```markdown
# Background Interactions & Polling

Run long tasks asynchronously and retrieve results later.

## When to Use Background Interactions

Use background mode for tasks that may take more than a few seconds:
- Complex code execution
- Large document processing
- Long-form content generation

## Starting a Background Interaction

Set `background: true` and `store: true`:

```swift
var request = InteractionRequest(input: .text("Write a detailed report on climate change."))
request.model = "gemini-2.5-flash-preview-05-20"
request.background = true
request.store = true

let initial = try await client.send(request)
print("Started: \(initial.id), status: \(initial.status.rawValue)")
// status is typically .inProgress
```

**Both flags are required.** Without `store: true`, the interaction cannot be retrieved after the initial response.

## Polling for Completion

`client.poll()` calls `client.get()` in a loop until the interaction reaches a terminal status:

```swift
let completed = try await client.poll(
    id: initial.id,
    timeout: .seconds(120),
    interval: .seconds(3)
)
print(completed.outputText ?? "")
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `timeout` | `.seconds(300)` | Maximum wait time before throwing `.pollTimeout` |
| `interval` | `.seconds(5)` | Time between `get()` calls |

Terminal statuses (any of these stops polling):

| Status | Meaning |
|--------|---------|
| `.completed` | Finished successfully |
| `.failed` | Model error |
| `.cancelled` | Cancelled via `client.cancel(id:)` |
| `.incomplete` | Stopped early (e.g., max output tokens) |
| `.budgetExceeded` | Token/cost budget exceeded |

## Webhooks

Instead of polling, receive a notification when the interaction completes:

```swift
request.webhookConfig = WebhookConfig(
    notificationEndpoints: ["https://your-server.example.com/gemini-webhook"],
    userMetadata: ["job_id": "report-001"]
)
```

The API POSTs the completed `Interaction` as JSON to your endpoint. Respond with HTTP 200 to acknowledge.

## Managing Interactions

Retrieve, cancel, or delete stored interactions:

```swift
// Retrieve
let interaction = try await client.get(id: "v1_abc123")

// Cancel (stops in-progress work)
try await client.cancel(id: "v1_abc123")

// Delete (removes from storage)
try await client.delete(id: "v1_abc123")
```

## What's Next

- [Traits](traits.md) — selective compilation for smaller binaries
- [Error Handling](error-handling.md) — handling poll timeouts and failures
```

- [ ] **Step 2: Commit**

```bash
git add docs/background-and-polling.md
git commit -m "docs: add background-and-polling guide"
```

---

### Task 9: Update docs/traits.md

**Files:**
- Modify: `docs/traits.md`

- [ ] **Step 1: Add guide cross-references to docs/traits.md**

At the end of the file (before the `### Migration` section), add a new section:

```markdown
### Guide Coverage by Trait

| Feature | Guide | Required Trait |
|---------|-------|----------------|
| Client, send, get, delete, cancel | [Getting Started](getting-started.md) | None (always available) |
| Streaming | [Streaming](streaming.md) | None (always available) |
| Polling | [Background & Polling](background-and-polling.md) | None (always available) |
| ToolSession | [Tools](tools.md) | `ToolSession` |
| Agent | [Agent](agent.md) | `Agent` |
```

- [ ] **Step 2: Commit**

```bash
git add docs/traits.md
git commit -m "docs: add guide cross-references to traits doc"
```

---

### Task 10: AGENTS.md

**Files:**
- Create: `AGENTS.md`

- [ ] **Step 1: Write AGENTS.md**

```markdown
# AGENTS.md — SwiftGeminiInteractions

Machine-readable patterns and pitfalls for AI coding tools.

## Project Overview

SwiftGeminiInteractions is a Swift client for the Gemini Interactions API. It provides:
- `InteractionsClient` — actor for HTTP communication (send, stream, get, delete, cancel, poll)
- `ToolSession` — automatic tool-calling loop with parallel execution (requires `ToolSession` trait)
- `Agent` — multi-turn conversation wrapper with automatic chaining and transcripts (requires `Agent` trait)

**Package:** `SwiftGeminiInteractions` (single library product)
**Minimum:** macOS 13 / iOS 16, Swift 6.3
**Default trait:** `Full` (enables both `ToolSession` and `Agent`)

### Source Files

| File | Trait gate | Contents |
|------|------------|----------|
| `Sources/SwiftGeminiInteractions/Core.swift` | always | All types, config params, result builders, InteractionsClient |
| `Sources/SwiftGeminiInteractions/Streaming.swift` | always | SSE parser, stream(), resumeStream() |
| `Sources/SwiftGeminiInteractions/BackgroundPolling.swift` | always | poll() |
| `Sources/SwiftGeminiInteractions/ToolSession.swift` | `#if ToolSession` | ToolSession, ToolSessionResult, ToolSessionEvent |
| `Sources/SwiftGeminiInteractions/Agent.swift` | `#if Agent` | Agent, AgentTool, AgentToolBuilder, TranscriptEntry |

---

## Basic Request

### Pattern

```swift
import SwiftGeminiInteractions

let client = InteractionsClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)
var request = InteractionRequest(input: .text("Hello"))
request.model = "gemini-2.5-flash-preview-05-20"
let interaction = try await client.send(request)
let output = interaction.outputText ?? ""
```

### Pitfalls
- `InteractionsClient` is an actor. All methods are async.
- `InteractionRequest.init` requires `input:`. Model is set separately via `request.model`.
- `outputText` is a convenience that extracts the last text from the last `.modelOutput` step. It can be `nil`.

---

## Streaming

### Pattern

```swift
var request = InteractionRequest(input: .text("Tell me a story"))
request.model = "gemini-2.5-flash-preview-05-20"

for try await event in client.stream(request) {
    if case .stepDelta(let delta, _) = event,
       case .text(let text) = delta {
        print(text, terminator: "")
    }
}
```

### Pitfalls
- `client.stream()` automatically sets `stream: true` and `store: true`. Do not set these manually.
- Always handle `.unknown` events gracefully — new event types may be added. The SSE parser silently drops `.unknown`.
- `resumeStream(id:lastEventId:)` requires the interaction ID from `.interactionCreated` and the last event ID you processed.

---

## Tools (ToolSession)

### Pattern

```swift
// Requires ToolSession trait (enabled by default)
import SwiftGeminiInteractions

@LLMTool("get_weather", "Returns current weather for a city")
struct GetWeather {
    struct Arguments: Decodable { let city: String }
    func call(arguments: Arguments) async throws -> ToolOutput {
        return ToolOutput("{\"temperature\": 22}")
    }
}

let tool = InteractionTool(GetWeather.toolDefinition)
let session = ToolSession(
    client: client,
    tools: [tool],
    handlers: ["get_weather": { args in
        let decoded = try JSONDecoder().decode(GetWeather.Arguments.self, from: args.data(using: .utf8)!)
        let result = try await GetWeather().call(arguments: decoded)
        return result.content
    }]
)

let result = try await session.run(
    model: "gemini-2.5-flash-preview-05-20",
    input: [User("What's the weather in Tokyo?")],
    configParams: []
)
```

### Pitfalls
- `ToolSession` manages `previousInteractionId` and `store: true` automatically. Do NOT pass `PreviousInteractionId` or `Store` in `configParams`.
- Handler closures receive a raw JSON **string**, not decoded arguments. You must decode within the handler.
- Built-in tools (`.googleSearch`, `.codeExecution`, etc.) do NOT need handlers. Only `.function` tools need handlers.
- If a handler throws, ToolSession catches it and sends the error back to the model as a function result with `isError: true`. The loop continues.
- Tool calls within a single iteration are executed concurrently via `TaskGroup`.

---

## Agent

### Pattern

```swift
// Requires Agent trait (enabled by default)
let agent = try Agent(
    client: client,
    model: "gemini-2.5-flash-preview-05-20",
    instructions: "You are a helpful assistant."
) {
    AgentTool(GetWeather())
} config: {
    Temperature(0.7)
}

let reply = try await agent.send("What's the weather?")
// Agent automatically chains via previousInteractionId
let followUp = try await agent.send("What about tomorrow?")
```

### Pitfalls
- `Agent` manages `previousInteractionId`, `store`, and `systemInstruction` automatically. Do NOT pass `PreviousInteractionId`, `Store`, or `SystemInstruction` in config params — they will be overwritten.
- `Agent` is an `actor`. All properties (`transcript`, `lastUsage`, `lastInteractionId`) are accessed with `await`.
- Duplicate tool names in the `tools:` builder throw at init time.
- `AgentTool(SomeLLMTool())` is the preferred way to create tools. It handles argument decoding and output extraction.
- `agent.reset()` clears the conversation chain, transcript, and usage. Call it to start a new conversation.
- For named agents: use `Agent(client:agent:)` instead of `Agent(client:model:)`.

---

## Configuration

### Pattern

```swift
// Direct application
var request = InteractionRequest(input: .text("Hello"))
Temperature(0.7).apply(to: &request)
MaxOutputTokens(1024).apply(to: &request)

// Result builder (with Agent)
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    // tools
} config: {
    Temperature(0.7)
    MaxOutputTokens(1024)
    ThinkingLevelParam(.high)
}
```

### All 17 Config Parameters

**GenerationConfig:** `Temperature(Double)`, `TopP(Double)`, `MaxOutputTokens(Int)`, `Seed(Int)`, `ThinkingLevelParam(ThinkingLevel)`, `ThinkingSummariesParam(ThinkingSummaries)`

**Request-level:** `SystemInstruction(String)`, `PreviousInteractionId(String)`, `Store(Bool)`, `Background(Bool)`, `ServiceTierParam(ServiceTier)`, `ResponseFormatParam(ResponseFormat)`, `ResponseModalitiesParam([ResponseModality])`, `EnvironmentParam(EnvironmentConfig)`, `WebhookConfigParam(WebhookConfig)`

**No-op (read by orchestration):** `MaxToolCalls(Int)`, `RequestTimeout(TimeInterval)`

### Structured Output

```swift
let schema = JSONSchemaValue.object(
    properties: [
        ("name", .string(description: "Name")),
        ("age", .integer(description: "Age"))
    ],
    required: ["name", "age"]
)
request.responseFormat = .text(mimeType: "application/json", schema: schema)
```

### Pitfalls
- Out-of-range values are silently ignored: `Temperature(5.0)` does nothing because 5.0 > 2.0.
- Empty strings and empty arrays are silently ignored: `SystemInstruction("")` does nothing.
- `GenerationConfig` fields are set via `request.ensureGenerationConfig()` + field assignment. Don't set `request.generationConfig` directly if you're also using config params — they may overwrite each other.

---

## Background Interactions

### Pattern

```swift
var request = InteractionRequest(input: .text("Long task"))
request.model = "gemini-2.5-flash-preview-05-20"
request.background = true
request.store = true

let initial = try await client.send(request)
let completed = try await client.poll(id: initial.id, timeout: .seconds(120), interval: .seconds(3))
```

### Pitfalls
- Both `background: true` AND `store: true` are required. Without `store`, the interaction cannot be retrieved later.
- `poll()` throws `.pollTimeout(id:)` if the timeout is exceeded.
- `client.get(id:)` retrieves a stored interaction. `client.cancel(id:)` cancels an in-progress one. `client.delete(id:)` removes it.

---

## Testing

### Pattern

```swift
import XCTest
@testable import SwiftGeminiInteractions

// MockURLProtocol intercepts all URLSession requests
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
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

// Create a test client using the internal init that accepts a URLSession
func makeTestClient() -> InteractionsClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return InteractionsClient(apiKey: "test-key", session: URLSession(configuration: config))
}

// Set up mock response
MockURLProtocol.requestHandler = { _ in
    let json = """
    {"id":"v1_test","object":"interaction","status":"completed",
     "steps":[{"type":"model_output","content":[{"type":"text","text":"Hello!"}]}]}
    """.data(using: .utf8)!
    return (HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, json)
}
let client = makeTestClient()
let interaction = try await client.send(InteractionRequest(input: .text("Hi")))
XCTAssertEqual(interaction.outputText, "Hello!")
```

### Pitfalls
- The test client uses an **internal** `init(apiKey:apiRevision:session:)` that accepts a `URLSession`. You need `@testable import` to access it.
- Always set `MockURLProtocol.requestHandler` before making requests. Reset to `nil` in `tearDown`.
- Integration tests require `GEMINI_API_KEY` env var and `RUN_INTEGRATION_TESTS=1`.

---

## Common Mistakes

1. **Setting `PreviousInteractionId` with Agent or ToolSession** — both manage chaining automatically. Your param will be overwritten.

2. **Forgetting `store: true` for manual multi-turn** — `previousInteractionId` requires the previous interaction to be stored. Without `store: true`, the chain breaks.

3. **Registering handlers for built-in tools** — `.googleSearch`, `.codeExecution`, etc. execute server-side. If you register a handler for them, it will never be called.

4. **Using `#if Agent` or `#if ToolSession` without enabling traits** — if a consumer declares `traits: []` in Package.swift, all trait-gated code is excluded. Use `#if Agent` / `#if ToolSession` guards only in library code.

5. **Wrapping `GeminiInteractionsError`** — all errors from the public API are already `GeminiInteractionsError`. Re-wrapping loses the specific case. Catch and switch on the error directly.

6. **Setting `request.generationConfig` directly while also using config params** — config params like `Temperature(0.7)` call `request.ensureGenerationConfig()` and set individual fields. If you also set `request.generationConfig = GenerationConfig(...)`, you may overwrite param-set fields or vice versa. Pick one approach.

7. **Not handling `.unknown` in stream events** — new event types are added for forward compatibility. Always have a `default` case in your switch.
```

- [ ] **Step 2: Commit**

```bash
git add AGENTS.md
git commit -m "docs: add AGENTS.md for AI coding tools"
```

---

### Task 11: Remove old docs

**Files:**
- Remove: `docs/built-in-tools.md`
- Remove: `docs/structured-output.md`
- Remove: `docs/background-interactions.md`

- [ ] **Step 1: Delete the old docs**

```bash
git rm docs/built-in-tools.md docs/structured-output.md docs/background-interactions.md
```

- [ ] **Step 2: Commit**

```bash
git commit -m "docs: remove old docs folded into new guides"
```

---

### Task 12: DocC Comments — Core.swift (Types and Enums)

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/Core.swift`

- [ ] **Step 1: Add DocC comments to error enum, status types, and foundational types**

Add `///` comments to:

```swift
/// Errors thrown by all SwiftGeminiInteractions public API methods.
public enum GeminiInteractionsError: Error, LocalizedError, @unchecked Sendable {
    /// Network connectivity failure (no internet, DNS resolution, timeout).
    case networkError(URLError)
    /// Non-2xx HTTP response. Status code 429 is reported as `.rateLimitExceeded` instead.
    case httpError(statusCode: Int, body: String)
    /// HTTP 429 — too many requests.
    case rateLimitExceeded
    /// Response JSON could not be decoded into the expected type.
    case decodingError(DecodingError)
    /// Request could not be encoded to JSON.
    case encodingError(EncodingError)
    /// Caller-provided input is invalid (e.g., duplicate tool names).
    case invalidInput(String)
    /// A tool handler threw during execution.
    case toolExecutionFailed(name: String, error: any Error)
    /// The tool-calling loop exceeded the configured maximum iterations.
    case maxIterationsExceeded(Int)
    /// `poll()` exceeded its timeout without reaching a terminal status.
    case pollTimeout(id: String)
    /// The interaction reached a non-success terminal status.
    case interactionFailed(id: String, status: InteractionStatus)
```

```swift
/// The processing state of an interaction.
public enum InteractionStatus: String, Codable, Sendable {
```

```swift
/// Processing tier that controls latency and cost trade-offs.
public enum ServiceTier: String, Codable, Sendable {
```

```swift
/// Output modality requested in a response.
public enum ResponseModality: String, Codable, Sendable {
```

```swift
/// Controls how much the model reasons before responding.
public enum ThinkingLevel: String, Codable, Sendable {
```

```swift
/// Whether thinking summaries are included in the response.
public enum ThinkingSummaries: String, Codable, Sendable {
```

```swift
/// Controls whether the model must, may, or cannot call tools.
public enum ToolChoiceMode: String, Codable, Sendable {
```

```swift
/// Configuration for tool choice behavior, including optional tool name filtering.
public struct ToolChoiceConfig: Codable, Sendable {
```

```swift
/// Token count for a specific modality (text, image, audio, etc.).
public struct ModalityTokens: Codable, Sendable {
```

```swift
/// Count of grounding tool invocations by type.
public struct GroundingToolCount: Codable, Sendable {
```

```swift
/// A citation or annotation attached to model output text.
public enum Annotation: Sendable {
```

```swift
/// A piece of content within a step — text, image, document, audio, or video.
public enum Content: Sendable {
```

```swift
/// A web search result returned by the Google Search built-in tool.
public struct GoogleSearchResult: Codable, Sendable {
```

```swift
/// A file search result returned by the File Search built-in tool.
public struct FileSearchResult: Codable, Sendable {
```

- [ ] **Step 2: Add DocC comments to Step enum**

```swift
/// A single step in an interaction's conversation history.
///
/// Steps represent everything that can appear in a conversation: user input, model output,
/// tool calls and results, and built-in tool invocations. The `type` field in the JSON
/// determines which case is decoded.
public enum Step: Sendable {
```

- [ ] **Step 3: Add DocC comments to InteractionTool, InteractionInput, GenerationConfig, ResponseFormat**

```swift
/// A tool the model can use — either a client-defined function or a server-side built-in.
public enum InteractionTool: Codable, Sendable {
```

```swift
/// Convenience initializer from a `ToolDefinition` produced by the `@LLMTool` macro.
public extension InteractionTool {
    init(_ definition: ToolDefinition) {
```

```swift
/// The input to an interaction — either a simple text string or an array of steps.
public enum InteractionInput: Codable, Sendable {
```

```swift
/// Generation parameters that control model output (temperature, token limits, thinking, etc.).
public struct GenerationConfig: Codable, Sendable {
```

```swift
/// How binary content (images, audio) is delivered in the response.
public enum ResponseDelivery: String, Codable, Sendable {
```

```swift
/// MIME types for audio output.
public enum AudioOutputMimeType: String, Codable, Sendable {
```

```swift
/// The format of the model's response — text (optionally JSON-constrained), image, or audio.
public enum ResponseFormat: Sendable {
```

- [ ] **Step 4: Add DocC comments to InteractionRequest, Usage, Interaction**

```swift
/// A request to the Gemini Interactions API.
public struct InteractionRequest: Codable, Sendable {
```

```swift
/// Token usage statistics for an interaction.
public struct Usage: Codable, Sendable {
```

```swift
/// The response from the Gemini Interactions API — contains the conversation steps, status, and usage.
public struct Interaction: Codable, Sendable {
```

```swift
/// The last text output from the model, or `nil` if no text was produced.
public var outputText: String? {
```

```swift
/// Whether the interaction requires tool call results before it can continue.
public var requiresAction: Bool { status == .requiresAction }
```

```swift
/// All `.functionCall` steps in this interaction.
public var functionCalls: [Step] {
```

```swift
/// Whether the interaction has reached a terminal status.
public var isComplete: Bool {
```

- [ ] **Step 5: Add DocC comments to convenience constructors and config protocol**

```swift
/// Creates a `.userInput` step with a single text content item.
public func User(_ text: String) -> Step {
```

(This one already has a comment — verify it exists.)

```swift
/// A type that can modify an `InteractionRequest` before it is sent.
///
/// Implement `apply(to:)` to set fields on the request. Config parameters are
/// composed using the `@InteractionConfigBuilder` result builder.
public protocol InteractionConfigParameter: Sendable {
```

- [ ] **Step 6: Add DocC comments to InteractionsClient public methods**

```swift
/// A client for the Gemini Interactions API.
///
/// `InteractionsClient` handles authentication, request encoding, error wrapping,
/// and HTTP transport. It is an actor and safe to share across tasks.
public actor InteractionsClient {
```

```swift
    /// Creates a client with the given API key.
    ///
    /// - Parameters:
    ///   - apiKey: Your Gemini API key.
    ///   - apiRevision: API version header sent with every request.
    public init(apiKey: String, apiRevision: String = "2026-05-20") {
```

```swift
    /// Sends a request and returns the completed interaction.
    ///
    /// - Parameter request: The interaction request to send.
    /// - Returns: The interaction response.
    /// - Throws: `GeminiInteractionsError` for network, HTTP, encoding, or decoding failures.
    public func send(_ request: InteractionRequest) async throws -> Interaction {
```

```swift
    /// Retrieves a stored interaction by ID.
    ///
    /// - Parameter id: The interaction ID.
    /// - Returns: The interaction.
    public func get(id: String) async throws -> Interaction {
```

```swift
    /// Deletes a stored interaction.
    ///
    /// - Parameter id: The interaction ID to delete.
    public func delete(id: String) async throws {
```

```swift
    /// Cancels an in-progress interaction.
    ///
    /// - Parameter id: The interaction ID to cancel.
    public func cancel(id: String) async throws {
```

- [ ] **Step 7: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiftGeminiInteractions/Core.swift
git commit -m "docs: add DocC comments to Core.swift types and client"
```

---

### Task 13: DocC Comments — Streaming.swift

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/Streaming.swift`

- [ ] **Step 1: Add DocC comments to streaming methods and types**

```swift
    /// Streams an interaction, yielding events as they arrive via Server-Sent Events.
    ///
    /// The request is automatically modified to set `stream: true` and `store: true`.
    ///
    /// - Parameter request: The interaction request to stream.
    /// - Returns: An async stream of `InteractionStreamEvent` values.
    public nonisolated func stream(_ request: InteractionRequest) -> AsyncThrowingStream<InteractionStreamEvent, Error> {
```

```swift
    /// Resumes a previously interrupted stream from the last received event.
    ///
    /// - Parameters:
    ///   - id: The interaction ID from the original stream.
    ///   - lastEventId: The ID of the last event successfully processed.
    /// - Returns: An async stream continuing from after the specified event.
    public nonisolated func resumeStream(
```

```swift
/// An incremental content update within a streaming step.
public enum InteractionStreamDelta: Sendable {
```

```swift
/// A streaming event from the Gemini Interactions API, delivered via Server-Sent Events.
public enum InteractionStreamEvent: Codable, Sendable {
```

- [ ] **Step 2: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftGeminiInteractions/Streaming.swift
git commit -m "docs: add DocC comments to Streaming.swift"
```

---

### Task 14: DocC Comments — BackgroundPolling.swift

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/BackgroundPolling.swift`

- [ ] **Step 1: Add DocC comments to poll()**

```swift
    /// Polls a stored interaction until it reaches a terminal status.
    ///
    /// Calls `get(id:)` in a loop, sleeping for `interval` between checks.
    /// Throws `.pollTimeout(id:)` if `timeout` is exceeded.
    ///
    /// - Parameters:
    ///   - id: The interaction ID to poll.
    ///   - timeout: Maximum wait time (default: 300 seconds).
    ///   - interval: Time between poll attempts (default: 5 seconds).
    /// - Returns: The completed interaction.
    public func poll(
```

- [ ] **Step 2: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftGeminiInteractions/BackgroundPolling.swift
git commit -m "docs: add DocC comments to BackgroundPolling.swift"
```

---

### Task 15: DocC Comments — ToolSession.swift

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/ToolSession.swift`

- [ ] **Step 1: Add DocC comments to ToolSession types**

```swift
/// A record of a single tool call during a `ToolSession` run.
public struct ToolCallLogEntry: Sendable {
```

```swift
/// The result of a complete `ToolSession.run()` — includes the final interaction, iteration count, tool call log, and per-iteration usage.
public struct ToolSessionResult: Sendable {
```

```swift
    /// Token usage summed across all iterations.
    public var totalUsage: Usage? {
```

```swift
/// Events yielded by `ToolSession.stream()` — combines LLM streaming events with tool execution lifecycle.
public enum ToolSessionEvent: Sendable {
```

```swift
/// Runs an automatic tool-calling loop: send, check for function calls, execute handlers, chain results, repeat.
public struct ToolSession: Sendable {
```

```swift
    /// The type signature for tool handler closures.
    public typealias ToolHandler = @Sendable (String) async throws -> String
```

```swift
    /// Runs the tool-calling loop synchronously (non-streaming).
    ///
    /// - Parameters:
    ///   - model: The model identifier string.
    ///   - input: Initial conversation steps.
    ///   - configParams: Config parameters applied to each request.
    /// - Returns: The final result including interaction, log, and usage.
    public func run(
```

```swift
    /// Streams the tool-calling loop, yielding events for each iteration, tool call, and LLM event.
    ///
    /// - Parameters:
    ///   - model: The model identifier string.
    ///   - input: Initial conversation steps.
    ///   - configParams: Config parameters applied to each request.
    /// - Returns: An async stream of `ToolSessionEvent` values.
    public func stream(
```

- [ ] **Step 2: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftGeminiInteractions/ToolSession.swift
git commit -m "docs: add DocC comments to ToolSession.swift"
```

---

### Task 16: DocC Comments — Agent.swift

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/Agent.swift`

- [ ] **Step 1: Add DocC comments to Agent types**

```swift
/// Pairs an `InteractionTool` with a handler closure for use with `Agent`.
public struct AgentTool: Sendable {
```

```swift
    /// Creates an `AgentTool` from an `@LLMTool`-conforming type, extracting the tool definition and wrapping the `call` method as a handler.
    public init<T: LLMTool>(_ instance: T) {
```

```swift
/// Result builder for composing `[AgentTool]` arrays in `Agent` initializers.
public struct AgentToolBuilder {
```

```swift
/// A log entry in an `Agent`'s conversation transcript.
public enum TranscriptEntry: Sendable {
```

```swift
/// A multi-turn conversational agent that wraps `ToolSession` with automatic interaction chaining, transcript tracking, and usage aggregation.
///
/// `Agent` is an actor. Use `send(_:)` for synchronous (non-streaming) requests
/// or `stream(_:)` for real-time event streaming. Both automatically chain interactions
/// via `previousInteractionId`.
public actor Agent {
```

```swift
    /// Sends a message and returns the model's text output.
    ///
    /// Automatically chains to the previous interaction if one exists.
    ///
    /// - Parameter message: The user's message text.
    /// - Returns: The model's text response.
    public func send(_ message: String) async throws -> String {
```

```swift
    /// Streams a message, yielding `ToolSessionEvent` values in real time.
    ///
    /// - Parameter message: The user's message text.
    /// - Returns: An async stream of events.
    public func stream(_ message: String) -> AsyncThrowingStream<ToolSessionEvent, Error> {
```

```swift
    /// Resets the agent's conversation state — clears the interaction chain, transcript, and usage.
    public func reset() {
```

- [ ] **Step 2: Verify build succeeds**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/SwiftGeminiInteractions/Agent.swift
git commit -m "docs: add DocC comments to Agent.swift"
```

---

### Task 17: Final Verification

**Files:** (none modified)

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: All tests pass (126+ tests). DocC comments don't affect runtime behavior.

- [ ] **Step 2: Verify all guide links resolve**

Run:
```bash
grep -oh '\[.*\](.*\.md)' README.md docs/*.md AGENTS.md | grep -oP '\(.*?\)' | tr -d '()' | sort -u | while read -r link; do
  # Resolve relative to the file's directory
  if [ ! -f "$link" ] && [ ! -f "docs/$link" ]; then
    echo "BROKEN: $link"
  fi
done
```

Expected: No "BROKEN" output.

- [ ] **Step 3: Verify old docs are gone**

Run: `ls docs/built-in-tools.md docs/structured-output.md docs/background-interactions.md 2>&1`
Expected: "No such file or directory" for all three.

- [ ] **Step 4: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "docs: fix any issues found during verification"
```
