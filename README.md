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
