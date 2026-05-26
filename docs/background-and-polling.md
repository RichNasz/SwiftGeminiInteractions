# Background and Polling

Background interactions allow you to submit long-running requests to the Gemini API and retrieve results asynchronously. Instead of waiting for a response, your app receives an in-progress interaction immediately and can poll for completion or use webhooks for notification.

## When to Use Background Interactions

Background interactions are ideal for tasks that take significant time to complete:

- **Complex code execution** — Running compute-intensive programs or processing large datasets
- **Large document processing** — Analyzing lengthy PDFs, transcripts, or multi-file codebases
- **Long-form generation** — Creating comprehensive reports, essays, or documentation that requires extended model thinking time

For quick queries or real-time conversations, use standard synchronous requests or streaming instead.

## Starting a Background Interaction

To start a background interaction, you must set **both** `background: true` and `store: true` in your request. The `store` flag is required so the interaction can be retrieved later.

```swift
import SwiftGeminiInteractions

let client = InteractionsClient(apiKey: "YOUR_API_KEY")

let request = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("Write a comprehensive analysis of quantum computing developments in 2026."))
    Background(true)
    Store(true)
}

let initial = try await client.send(request)
print("Interaction ID: \(initial.id)")
print("Status: \(initial.status.rawValue)")  // typically "inProgress"
```

The `send()` call returns immediately with an `Interaction` that has `.inProgress` status. Save the `id` to poll for completion or manage the interaction later.

**Important**: Both flags are required together. Without `store: true`, the background interaction cannot be fetched after submission.

## Polling for Completion

Use `client.poll(id:timeout:interval:)` to wait for a background interaction to complete. The method repeatedly calls `get()` until the interaction reaches a terminal status.

```swift
let completed = try await client.poll(
    id: initial.id,
    timeout: .seconds(300),
    interval: .seconds(5)
)

if let output = completed.outputText {
    print("Result: \(output)")
} else {
    print("Status: \(completed.status.rawValue)")
}
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `timeout` | `.seconds(300)` | Maximum time to wait before throwing `pollTimeout` error |
| `interval` | `.seconds(5)` | Time between polling attempts (avoid hammering the API) |

If polling exceeds the timeout, `poll()` throws `GeminiInteractionsError.pollTimeout(id:)`.

### Terminal Statuses

Polling stops when the interaction reaches any terminal status. Check `interaction.isComplete` or inspect the status directly:

| Status | Description |
|--------|-------------|
| `.completed` | The interaction finished successfully |
| `.failed` | The model encountered an error during processing |
| `.cancelled` | The interaction was cancelled via `client.cancel(id:)` |
| `.incomplete` | The model stopped before finishing (e.g., max output tokens hit) |
| `.budgetExceeded` | Token or cost budget was exceeded |

## Webhooks

Instead of polling, you can provide webhook URLs for the API to notify you when an interaction completes. This eliminates the need for your app to poll entirely.

```swift
let request = InteractionRequest {
    Model("gemini-2.5-flash-preview-05-20")
    Input(.text("Generate a detailed report on climate trends."))
    Background(true)
    Store(true)
    WebhookConfig(
        notificationEndpoints: ["https://your-server.example.com/gemini-webhook"],
        userMetadata: ["job_id": "report-2026-05-25", "user": "alice"]
    )
}

let initial = try await client.send(request)
// Your webhook will receive the completed interaction
```

The API POSTs the completed `Interaction` object as JSON to your webhook endpoint. Your server must respond with HTTP 200 to acknowledge receipt.

The optional `userMetadata` dictionary lets you attach custom identifiers or context that will be included in the webhook payload, making it easier to route or process completed interactions.

## Managing Interactions

The `InteractionsClient` provides methods to retrieve, cancel, and delete stored interactions.

### Get Interaction

Retrieve the current state of any stored interaction by its ID:

```swift
let interaction = try await client.get(id: "interaction-id-here")
print("Current status: \(interaction.status.rawValue)")
```

### Cancel Interaction

Cancel an in-progress interaction:

```swift
try await client.cancel(id: "interaction-id-here")

// Verify cancellation
let cancelled = try await client.get(id: "interaction-id-here")
print(cancelled.status)  // .cancelled
```

Cancelling stops model processing but does not delete the interaction from storage. Use `delete()` to remove it.

### Delete Interaction

Permanently remove a stored interaction:

```swift
try await client.delete(id: "interaction-id-here")

// Subsequent get() will fail
do {
    _ = try await client.get(id: "interaction-id-here")
} catch {
    print("Interaction deleted")  // Error thrown: not found
}
```

Deletion is permanent and cannot be undone. Only delete interactions when you no longer need their results or history.

## What's Next

- [Traits](traits.md) — Learn about the modular trait system for enabling optional features
- [Error Handling](error-handling.md) — Understand error types and recovery strategies
