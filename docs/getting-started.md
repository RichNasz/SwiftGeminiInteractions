---
status: alpha
---

# Getting Started

This guide walks you through the basics of using SwiftGeminiInteractions to interact with the Gemini Interactions API.

## Creating an InteractionsClient

The `InteractionsClient` is an actor that manages all communication with the Gemini API:

```swift
import SwiftGeminiInteractions

let client = InteractionsClient(
    apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!
)
```

The client automatically sets the API revision to `2026-05-20`. You can override this if needed:

```swift
let client = InteractionsClient(
    apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!,
    apiRevision: "2026-06-01"
)
```

## Your First Request

Build an interaction request using the result builder syntax:

```swift
let request = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("What is the capital of France?"))
}

let interaction = try await client.send(request)
print(interaction.outputText)  // "Paris is the capital of France."
print(interaction.usage.totalTokens)  // e.g., 42
```

The `InteractionInput` enum has two forms:
- `.text(String)` — a simple string message from the user
- `.steps([Step])` — an array of Step values for multi-turn or complex scenarios

For convenience, use the `User()` function to create user input steps:

```swift
Input(.steps([
    User("What is the capital of France?")
]))
```

## Understanding the Response

The `Interaction` struct contains the full response from the API:

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Unique identifier for this interaction |
| `status` | `InteractionStatus` | Current status: `.processing`, `.complete`, `.failed`, `.cancelled` |
| `steps` | `[Step]` | All conversation steps (input + output) |
| `outputText` | `String` | Text output from the model (computed from `.modelOutput` steps) |
| `usage` | `Usage` | Token counts: `inputTokens`, `outputTokens`, `totalTokens` |
| `isComplete` | `Bool` | True when status is `.complete` |
| `functionCalls` | `[FunctionCall]` | All function calls in the response (computed from `.functionCall` steps) |

### The Step Enum

The `Step` enum has 17 cases organized into three categories:

**Input steps** (sent by you):
- `.userInput(UserInput)` — user message
- `.functionResult(FunctionResult)` — result from a function call

**Output steps** (received from the model):
- `.modelOutput(ModelOutput)` — text response from the model
- `.thought(Thought)` — internal reasoning (extended thinking mode)
- `.functionCall(FunctionCall)` — request to execute a function

**Built-in tool steps** (server-side execution):
- `.googleSearchCall(GoogleSearchCall)` / `.googleSearchResult(GoogleSearchResult)`
- `.codeExecutionCall(CodeExecutionCall)` / `.codeExecutionResult(CodeExecutionResult)`
- `.urlContextCall(URLContextCall)` / `.urlContextResult(URLContextResult)`
- `.fileSearchCall(FileSearchCall)` / `.fileSearchResult(FileSearchResult)`
- `.mcpToolCall(MCPToolCall)` / `.mcpToolResult(MCPToolResult)`

Use the `User()` convenience function to create `.userInput` steps without dealing with the full enum syntax:

```swift
let step = User("Hello!")  // Creates Step.userInput(UserInput(text: "Hello!"))
```

## Multi-turn Conversations

Chain interactions by referencing the previous interaction's ID and setting `store: true`:

```swift
// First turn
let request1 = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("My name is Alice."))
    Store(true)
}
let interaction1 = try await client.send(request1)

// Second turn — references first
let request2 = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("What is my name?"))
    Store(true)
    PreviousInteractionId(interaction1.id)
}
let interaction2 = try await client.send(request2)
print(interaction2.outputText)  // "Your name is Alice."
```

Alternatively, set the `previousInteractionId` property directly:

```swift
var request2 = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("What is my name?"))
}
request2.store = true
request2.previousInteractionId = interaction1.id
```

**Important**: `store` must be `true` for both the initial interaction and all follow-up interactions. Without it, the API won't persist the conversation history.

## What's Next

- [Streaming Responses](streaming.md) — Process responses as they arrive with server-sent events
- [Function Calling](tools.md) — Register custom tools and handle function calls with `ToolSession`
- [Agent Mode](agent.md) — Build autonomous agents with the `Agent` type
- [Configuration Reference](configuration.md) — All available configuration parameters
