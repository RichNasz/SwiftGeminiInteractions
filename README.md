# SwiftGeminiInteractions

[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%20%7C%20iOS%2016-lightgrey.svg)](Package.swift)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE-2.0.txt)
[![Version](https://img.shields.io/badge/Version-0.1.0--alpha.1-yellow.svg)](https://github.com/RichNasz/SwiftGeminiInteractions/releases/tag/v0.1.0-alpha.2)
[![Built with Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-blueviolet?logo=claude)](https://claude.ai/code)

A Swift client for the [Gemini Interactions API](https://ai.google.dev/gemini-api/docs/interactions) — send requests, stream responses, call tools, and run multi-turn agents.

## Release Status

**0.1.0-alpha.2** — Early adopter software. The API may change between alpha releases as it is exercised in real applications. Feedback and issues are welcome.

## Install

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/RichNasz/SwiftGeminiInteractions.git", from: "0.1.0-alpha.2")
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
