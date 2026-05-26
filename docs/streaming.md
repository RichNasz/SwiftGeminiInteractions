# Streaming

Real-time event streaming lets you receive incremental updates as the model generates content, enabling responsive UIs and early processing of partial results.

## Basic Streaming

Call `client.stream(request)` to receive an `AsyncThrowingStream<InteractionStreamEvent, Error>`:

```swift
import SwiftGeminiInteractions

let client = InteractionsClient(apiKey: "your-api-key")

let request = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Steps {
        UserStep {
            TextPart("What are the key features of Swift concurrency?")
        }
    }
}

for try await event in client.stream(request) {
    switch event {
    case .interactionCreated(let interaction):
        print("Started interaction: \(interaction.id)")
        
    case .stepDelta(let delta, stepIndex: let index):
        if case .text(let text) = delta {
            print(text, terminator: "")
        }
        
    case .interactionCompleted(let interaction):
        print("\n\nCompleted with status: \(interaction.status)")
        
    default:
        break
    }
}
```

The client automatically sets `stream: true` and `store: true` on streaming requests.

## Event Types

| Event | Payload | When Emitted |
|-------|---------|--------------|
| `.interactionCreated(Interaction)` | Full interaction object | Stream starts, contains initial metadata |
| `.interactionStatusUpdate(InteractionStatus)` | New status | Status transitions (e.g., executing → completed) |
| `.stepStart(stepType: String, index: Int)` | Step type and position | New step begins generation |
| `.stepDelta(InteractionStreamDelta, stepIndex: Int)` | Content delta and position | Incremental content arrives |
| `.stepStop(index: Int)` | Step position | Step generation completes |
| `.interactionCompleted(Interaction)` | Final interaction state | Stream ends successfully |
| `.error(String)` | Error message | Server-side error occurred |
| `.unknown` | — | Unrecognized event type (forward compatibility) |

## Working with Deltas

The `InteractionStreamDelta` enum represents different types of incremental content:

| Delta Type | Contents | Use Case |
|------------|----------|----------|
| `.text(String)` | Text chunk | Model text generation |
| `.image(Data)` | Image bytes | Generated image data |
| `.functionCallArguments(delta: String, callId: String)` | Partial JSON + call ID | Function call construction |
| `.codeExecutionArguments(delta: String, id: String)` | Partial code + execution ID | Code execution step |
| `.googleSearchQuery(String)` | Search query text | Google Search tool usage |
| `.urlContextUrl(String)` | URL string | URL context tool usage |
| `.thoughtSummary(String)` | Thought text | Extended thinking step |
| `.annotation(Annotation)` | Grounding annotation | Citation/reference |
| `.unknown` | — | Unrecognized delta type |

**Text Accumulation Pattern:**

```swift
var textBuffer = ""

for try await event in client.stream(request) {
    switch event {
    case .stepDelta(let delta, stepIndex: _):
        if case .text(let chunk) = delta {
            textBuffer += chunk
            updateUI(with: textBuffer)
        }
        
    case .interactionCompleted:
        print("Final text: \(textBuffer)")
        
    default:
        break
    }
}
```

## Resuming Interrupted Streams

If a stream is interrupted, resume from the last received event using `client.resumeStream(id:lastEventId:)`:

```swift
var lastEventId: String?
var interactionId: String?

do {
    for try await event in client.stream(request) {
        if case .interactionCreated(let interaction) = event {
            interactionId = interaction.id
        }
        
        // Track last event ID from event metadata if available
        // (Implementation detail: event IDs are server-provided)
        
        // Process event...
    }
} catch {
    // Network interruption
    if let id = interactionId, let eventId = lastEventId {
        // Resume from last position
        for try await event in client.resumeStream(id: id, lastEventId: eventId) {
            // Continue processing...
        }
    }
}
```

The resumed stream will replay events starting after `lastEventId`, ensuring no content is missed.

## Error Handling in Streams

Streams have two error paths:

1. **Server-side errors** arrive as `.error(String)` events
2. **Network/HTTP errors** are thrown from the stream

```swift
do {
    for try await event in client.stream(request) {
        switch event {
        case .error(let message):
            // Server returned an error event
            print("Server error: \(message)")
            // Stream may continue or end depending on error type
            
        case .interactionCompleted(let interaction):
            if interaction.status == .failed {
                print("Interaction failed: \(interaction.failureMessage ?? "unknown")")
            }
            
        default:
            // Process other events...
            break
        }
    }
} catch let error as GeminiInteractionsError {
    // Network failure, HTTP error, or JSON decoding issue
    switch error {
    case .networkError(let underlying):
        print("Network failed: \(underlying)")
    case .httpError(let statusCode, let message):
        print("HTTP \(statusCode): \(message)")
    case .decodingError(let underlying):
        print("Invalid response: \(underlying)")
    default:
        print("Stream error: \(error)")
    }
} catch {
    print("Unexpected error: \(error)")
}
```

## What's Next

- [Tools & Function Calling](tools.md) — Handle function calls in streaming responses
- [Agent](agent.md) — Autonomous tool execution with streaming support
