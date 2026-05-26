---
status: alpha
---

# how-errors.md — Error Wrapping Strategy

## No Foundation errors escape the public API
Every throw site in `InteractionsClient` wraps Foundation errors into `GeminiInteractionsError` before propagating to callers. Callers only ever see `GeminiInteractionsError` (or `CancellationError` from `Task` cooperative cancellation, which is not wrapped).

## URLError wrapping
In `InteractionsClient.execute(_:)`, the `session.data(for:)` call is wrapped in `do/catch`. A caught `URLError` is rethrown as `GeminiInteractionsError.networkError(urlError)`. The associated value is the original `URLError` so callers can inspect `.code` and `.localizedDescription`.

## HTTP 429
When `execute` receives an `HTTPURLResponse` with status code 429, it throws `GeminiInteractionsError.rateLimitExceeded`. No body is read or inspected for this specific case.

## HTTP non-2xx (other than 429)
When the status code is outside 200–299 and not 429, `execute` reads the response body as a UTF-8 string (falling back to an empty string) and throws `GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: bodyString)`.

## DecodingError wrapping
`InteractionsClient.decode(_:from:)` (private helper) catches `DecodingError` and rethrows as `GeminiInteractionsError.decodingError(decodingError)`. The original `DecodingError` is preserved in the associated value.

## EncodingError wrapping
`InteractionsClient.encode(_:)` (private helper) catches `EncodingError` and rethrows as `GeminiInteractionsError.encodingError(encodingError)`. The original `EncodingError` is preserved.

## Tool handler exceptions
Errors thrown by `ToolSession.ToolHandler` closures are caught **inside** the `withThrowingTaskGroup` child tasks. They are converted to the string `"Error: \(String(describing: error))"` and returned as the tool result with `isError = true`. They are **not** propagated as thrown errors and do not produce a `GeminiInteractionsError.toolExecutionFailed` case — that case exists in the error enum but is not currently used by the tool loop.

## @unchecked Sendable
`GeminiInteractionsError` is marked `@unchecked Sendable` because:
- `.networkError(URLError)`: `URLError` is `Sendable`, but `any Error` in the protocol-based form may not be.
- `.decodingError(DecodingError)`: `DecodingError` is not `Sendable`.
- `.encodingError(EncodingError)`: `EncodingError` is not `Sendable`.
- `.toolExecutionFailed(name: String, error: any Error)`: `any Error` existential is not `Sendable`.
Using `@unchecked Sendable` opts out of Swift's automatic Sendable checking while still allowing `GeminiInteractionsError` to cross actor isolation boundaries.

## maxIterationsExceeded
`GeminiInteractionsError.maxIterationsExceeded(Int)` carries the configured `maxIterations` limit (not the number of iterations that ran). Thrown by `ToolSession` when the loop reaches the limit.

## pollTimeout
`GeminiInteractionsError.pollTimeout(id: String)` carries the interaction ID that was being polled. Thrown by `InteractionsClient.poll` when the deadline is exceeded.

## invalidInput
`GeminiInteractionsError.invalidInput(String)` is used for programming errors detectable at runtime: e.g., duplicate tool names in `Agent` (message: `"Duplicate tool name: '\(name)'"`) and invalid UTF-8 in `AgentTool`'s `LLMTool` convenience init (message: `"Cannot decode arguments as UTF-8"`).
