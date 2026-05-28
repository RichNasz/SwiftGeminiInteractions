---
status: alpha
---

# Error Handling

SwiftGeminiInteractions wraps all errors in a single `GeminiInteractionsError` enum. No raw Foundation errors (like `URLError`, `DecodingError`, or `EncodingError`) escape the public API.

## Error Cases

All errors conform to `LocalizedError` and provide descriptive error messages via `localizedDescription`.

| Case | Description |
|------|-------------|
| `.networkError(URLError)` | Network connectivity failure (timeout, no internet, DNS failure, etc.) |
| `.httpError(statusCode:body:)` | Non-2xx HTTP response from the API |
| `.rateLimitExceeded` | HTTP 429 rate limit response |
| `.decodingError(DecodingError)` | Response JSON could not be decoded |
| `.encodingError(EncodingError)` | Request could not be encoded to JSON |
| `.invalidInput(String)` | Invalid input (e.g. duplicate tool names, invalid parameters) |
| `.toolExecutionFailed(name:error:)` | A tool handler threw an error (ToolSession/Agent) |
| `.maxIterationsExceeded(Int)` | ToolSession or Agent exceeded maximum iteration count |
| `.pollTimeout(id:)` | `poll()` exceeded timeout without reaching a terminal status |
| `.interactionFailed(id:status:)` | Interaction ended in a non-success terminal status (`.failed`, `.cancelled`, `.incomplete`, `.budgetExceeded`) |

## HTTP Errors

HTTP errors include the status code and response body. You can switch on the status code to handle specific cases:

```swift
do {
    let interaction = try await client.send(request)
    print(interaction.outputText)
} catch GeminiInteractionsError.httpError(let statusCode, let body) {
    switch statusCode {
    case 400:
        print("Bad request: \(body)")
    case 401:
        print("Unauthorized: check your API key")
    case 403:
        print("Forbidden: API key may lack permissions")
    case 404:
        print("Interaction not found")
    case 500...599:
        print("Server error: \(body)")
    default:
        print("HTTP \(statusCode): \(body)")
    }
} catch {
    print("Unexpected error: \(error)")
}
```

## Rate Limiting

HTTP 429 responses are retried automatically by `InteractionsClient` when a `RetryPolicy` is configured (the default). The client respects the `Retry-After` header when present and falls back to exponential backoff otherwise.

If all retry attempts are exhausted, `.rateLimitExceeded` is thrown. You only need to handle this case if you want to take action beyond the built-in retry:

```swift
do {
    let interaction = try await client.send(request)
} catch GeminiInteractionsError.rateLimitExceeded {
    print("Rate limit exceeded after all retry attempts")
}
```

To observe retry attempts as they happen, use the `onRetry` callback on `RetryPolicy`:

```swift
let client = InteractionsClient(apiKey: key, retryPolicy: RetryPolicy(
    onRetry: { event in
        print("Retry \(event.attempt)/\(event.maxAttempts), backing off \(event.backoffDuration)")
    }
))
```

See [Configuration — Retry Policy](configuration.md#retry-policy) for the full set of retry parameters.

## Tool Errors

When using `ToolSession` or `Agent`, tool handler errors are caught automatically and do not stop the loop. Instead:

1. The error is caught when the handler throws
2. A `.functionResult` step is created with `isError: true`
3. The error message is sent back to the model as the tool result
4. The loop continues, allowing the model to handle the error or retry

```swift
let session = ToolSession(
    client: client,
    tools: [InteractionTool(GetWeather.definition)],
    handlers: [
        "get_weather": { args in
            // If this throws, ToolSession catches it and sends the error back to the model
            guard let data = args.data(using: .utf8),
                  let params = try? JSONDecoder().decode(WeatherParams.self, from: data) else {
                throw WeatherError.invalidLocation
            }
            return try await fetchWeather(for: params.location)
        }
    ]
)

let result = try await session.run(
    model: "gemini-2.5-flash-preview-05-20",
    input: [User("What's the weather in Paris?")],
    configParams: []
)
```

### Max Iterations

If the tool-calling loop exceeds `maxIterations` (default: 10), `ToolSession.run()` throws `.maxIterationsExceeded`:

```swift
do {
    let result = try await session.run(
        model: "gemini-2.5-flash-preview-05-20",
        input: [User("Calculate factorial of 100000")],
        configParams: []
    )
} catch GeminiInteractionsError.maxIterationsExceeded(let limit) {
    print("Loop exceeded maximum iterations (\(limit)). The model may be stuck.")
}
```

You can increase the limit when creating the session:

```swift
let session = ToolSession(
    client: client,
    tools: tools,
    handlers: handlers,
    maxIterations: 20  // raise limit for complex multi-step tasks
)
```

## Polling Errors

When using `poll()` for background interactions, two error cases can occur:

### Poll Timeout

If the interaction doesn't complete within the timeout duration, `poll()` throws `.pollTimeout`:

```swift
do {
    let completed = try await client.poll(
        id: interaction.id,
        timeout: .seconds(60),
        interval: .seconds(3)
    )
    print(completed.outputText)
} catch GeminiInteractionsError.pollTimeout(let id) {
    print("Polling timed out for interaction: \(id)")
    // You can resume polling or cancel the interaction
    try await client.cancel(id: id)
}
```

### Interaction Failed

If the interaction completes but with a non-success status (`.failed`, `.cancelled`, `.incomplete`, `.budgetExceeded`), you'll receive the completed interaction. Check the status yourself:

```swift
let completed = try await client.poll(
    id: interaction.id,
    timeout: .seconds(120)
)

switch completed.status {
case .completed:
    print("Success: \(completed.outputText ?? "")")
case .failed:
    print("The interaction failed")
case .cancelled:
    print("The interaction was cancelled")
case .incomplete:
    print("The interaction stopped before completing (e.g., max tokens reached)")
case .budgetExceeded:
    print("Token or cost budget was exceeded")
default:
    print("Unexpected status: \(completed.status.rawValue)")
}
```

Note: `poll()` does **not** throw `.interactionFailed` — it returns the completed interaction regardless of status. You must check `interaction.status` yourself.

## All Errors Have Descriptions

Every `GeminiInteractionsError` case conforms to `LocalizedError` and provides a human-readable description:

```swift
do {
    let interaction = try await client.send(request)
} catch let error as GeminiInteractionsError {
    print(error.localizedDescription)
}

// Examples of localized descriptions:
// - "Network error: The request timed out."
// - "HTTP 401: Invalid API key"
// - "Rate limit exceeded. Retry after a short delay."
// - "Failed to decode response: The data couldn't be read because it is missing."
// - "Tool 'get_weather' failed: Network unavailable"
// - "Exceeded maximum tool iterations (10)."
// - "Poll timed out for interaction 'int_abc123'."
```

## What's Next

- [Background & Polling](background-and-polling.md) — Long-running tasks and webhooks
