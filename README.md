# SwiftGeminiInteractions

A Swift package for communicating with Gemini models using the [Gemini Interactions API](https://ai.google.dev/gemini-api/docs/interactions).

## Installation

Add to `Package.swift`:

```swift
.package(url: "https://github.com/your-org/SwiftGeminiInteractions.git", branch: "main")
```

And to your target's dependencies:

```swift
.product(name: "SwiftGeminiInteractions", package: "SwiftGeminiInteractions")
```

### Traits

By default you get all features. To reduce binary size, specify traits:

| Traits | What you get |
|--------|-------------|
| _(none specified)_ | Everything — `ToolSession`, `Agent`, streaming, polling |
| `["ToolSession"]` | Tool-calling loop, no `Agent` wrapper |
| `[]` | Core client only — `send()`, `stream()`, `get()`, `delete()`, `cancel()`, `poll()` |

```swift
// Core only — no tool orchestration
.package(url: "https://github.com/your-org/SwiftGeminiInteractions.git",
         branch: "main",
         traits: [])
```

See [docs/traits.md](docs/traits.md) for full details and design rationale.

## Quick Start

### Simple interaction

```swift
import SwiftGeminiInteractions

let client = InteractionsClient(apiKey: "YOUR_KEY")
var request = InteractionRequest(input: .text("What is the capital of France?"))
request.model = "gemini-2.5-flash-preview-05-20"
let interaction = try await client.send(request)
print(interaction.outputText ?? "")
// Tokens used: 42
print("Tokens used: \(interaction.usage?.totalTokens ?? 0)")
```

### Streaming

```swift
var request = InteractionRequest(input: .text("Tell me a story."))
request.model = "gemini-2.5-flash-preview-05-20"
for try await event in client.stream(request) {
    if case .stepDelta(let delta, _) = event,
       case .text(let text) = delta {
        print(text, terminator: "")
    }
}
```

### Agent with tools

```swift
import SwiftGeminiInteractions
import SwiftLLMToolMacros

@LLMTool("getWeather", "Returns current weather for a city")
struct WeatherTool {
    struct Arguments: Decodable { let city: String }
    func call(arguments: Arguments) async throws -> ToolOutput {
        .init("{\"temperature\": 22, \"condition\": \"sunny\"}")
    }
}

let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    AgentTool(WeatherTool())
}
let reply = try await agent.send("What's the weather in Tokyo?")
print(reply)
```

## Built-in Tools

Use server-side tools without writing handlers:

```swift
var request = InteractionRequest(input: .text("Search for recent Swift news."))
request.model = "gemini-2.5-flash-preview-05-20"
request.tools = [.googleSearch]
let interaction = try await client.send(request)
```

Available built-in tools: `.googleSearch`, `.codeExecution`, `.urlContext`, `.fileSearch(storeNames:topK:metadataFilter:)`, `.googleMaps(latitude:longitude:enableWidget:)`, `.mcpServer`.

## Background Interactions

Run long tasks in the background and poll for results:

```swift
var request = InteractionRequest(input: .text("Write a detailed report on climate change."))
request.model = "gemini-2.5-flash-preview-05-20"
request.background = true
request.store = true

let initial = try await client.send(request)
print("Started: \(initial.id)")

let completed = try await client.poll(
    id: initial.id,
    timeout: .seconds(120),
    interval: .seconds(3)
)
print(completed.outputText ?? "")
```

## Configuration

Use config params and result builder syntax for generation settings:

```swift
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20") {
    // tools...
} config: {
    Temperature(0.7)
    SystemInstruction("You are a helpful coding assistant.")
    MaxOutputTokens(2048)
}
```

Config params can also be applied directly to a request:

```swift
var request = InteractionRequest(input: .text("Hello"))
Temperature(0.5).apply(to: &request)
MaxOutputTokens(1024).apply(to: &request)
```

## Multi-turn Conversations

`Agent` automatically chains interactions via `previous_interaction_id`:

```swift
let agent = try Agent(client: client, model: "gemini-2.5-flash-preview-05-20")
let r1 = try await agent.send("What is Swift?")
let r2 = try await agent.send("How does it compare to Kotlin?")
// r2 has full context from r1
```

## Named Agents

Target a named Gemini agent instead of a model string:

```swift
let agent = try Agent(client: client, agent: "my-named-agent")
let reply = try await agent.send("Hello!")
```

## Stream Resumption

Resume a dropped stream from the last received event:

```swift
let stream = client.resumeStream(id: interactionId, lastEventId: lastEventId)
for try await event in stream {
    // handle events
}
```

## License

Licensed under the Apache License, Version 2.0. See [LICENSE-2.0.txt](LICENSE-2.0.txt).
