# Background Interactions

Background interactions let the Gemini API process a long-running request asynchronously. Your app submits the request, receives an in-progress interaction immediately, and then polls for completion.

## Requirements

Two flags are required together:

```swift
request.background = true
request.store = true   // required so the interaction can be retrieved later
```

Without `store: true`, the background interaction cannot be fetched after the initial response.

## Submitting a background request

```swift
let client = InteractionsClient(apiKey: "YOUR_API_KEY")

var request = InteractionRequest(input: .text("Write a comprehensive essay on climate change."))
request.model = "gemini-3-flash-preview"
request.background = true
request.store = true

let initial = try await client.send(request)
// initial.status is typically .inProgress at this point
print("Interaction ID: \(initial.id), status: \(initial.status.rawValue)")
```

## Polling for completion

`InteractionsClient.poll(id:timeout:interval:)` calls `get()` in a loop until the interaction reaches a terminal status, then returns it.

```swift
let completed = try await client.poll(
    id: initial.id,
    timeout: .seconds(120),
    interval: .seconds(3)
)
print(completed.outputText ?? "(no output)")
```

### Recommended values

| Parameter | Recommended | Notes |
|-----------|-------------|-------|
| `timeout` | `.seconds(120)` | Raise for very long tasks (essays, reports) |
| `interval` | `.seconds(3)` | Avoid hammering the API; 3–5 s is reasonable |

If `poll()` exceeds the timeout it throws `GeminiInteractionsError.pollTimeout(id:)`.

## Terminal statuses

`Interaction.isComplete` returns `true` for all terminal statuses. `poll()` stops as soon as it sees any of these:

| Status | Meaning |
|--------|---------|
| `completed` | The interaction finished successfully |
| `failed` | The model encountered an error |
| `cancelled` | The interaction was cancelled via `client.cancel(id:)` |
| `incomplete` | The model stopped before finishing (e.g. max output tokens hit) |
| `budgetExceeded` | The token or cost budget was exceeded |

## Webhook alternative

Instead of polling, you can provide a webhook URL. The API will POST the completed interaction to your endpoint, eliminating the need to poll entirely.

```swift
request.webhookConfig = WebhookConfig(
    notificationEndpoints: ["https://your-server.example.com/gemini-webhook"],
    userMetadata: ["job_id": "essay-001"]
)
```

The webhook payload is the completed `Interaction` object encoded as JSON. Your server should respond with HTTP 200 to acknowledge receipt.
