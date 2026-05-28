# Retry-with-Backoff — Design Spec

**Date:** 2026-05-27
**Status:** Approved

## Summary

Add retry-with-backoff support to `InteractionsClient`. When a request fails due to a retryable error (timeout, 429 rate limit, 500/503 server error), the client automatically retries with exponential backoff and growing timeouts.

## Motivation

Network requests to the Gemini API can fail transiently — server overload (429, 503), temporary outages (500), or slow responses (timeout). Currently, callers must implement their own retry logic. Built-in retry with sensible defaults eliminates this boilerplate and ensures consistent, correct retry behavior across all call sites.

## New Types

### RetryPolicy

```swift
public struct RetryPolicy: Sendable {
    public let maxAttempts: Int                              // default: 3
    public let initialBackoff: Duration                     // default: .seconds(2)
    public let backoffMultiplier: Double                    // default: 2.0
    public let initialTimeout: Duration                     // default: .seconds(120)
    public let timeoutMultiplier: Double                    // default: 1.5
    public let maxTimeout: Duration                         // default: .seconds(300)
    public let retryableStatusCodes: Set<Int>               // default: [429, 500, 503]
    public let onRetry: (@Sendable (RetryEvent) -> Void)?   // default: nil
}
```

- `maxAttempts`: Total attempts including the first. 3 means: try once, retry up to 2 more times.
- `initialBackoff`: Delay before the first retry.
- `backoffMultiplier`: Exponential multiplier. With defaults: 2s → 4s → 8s.
- `initialTimeout`: URLSession timeout for the first attempt.
- `timeoutMultiplier`: Timeout grows per attempt. With defaults: 120s → 180s → 270s.
- `maxTimeout`: Cap on timeout growth.
- `retryableStatusCodes`: HTTP status codes that trigger retry.
- `onRetry`: Optional callback invoked before each retry sleep. Receives a `RetryEvent` describing what happened.

### RetryEvent

```swift
public struct RetryEvent: Sendable {
    public let attempt: Int                    // 1-indexed attempt that just failed
    public let maxAttempts: Int                // total attempts allowed
    public let error: GeminiInteractionsError  // the error that triggered this retry
    public let backoffDuration: Duration       // how long we'll sleep before retrying
    public let nextTimeout: Duration           // timeout for the next attempt
}
```

## Changes to InteractionsClient

### Init

Add `retryPolicy: RetryPolicy?` parameter to both initializers:

```swift
public init(apiKey: String, apiRevision: String = "2026-05-20", retryPolicy: RetryPolicy? = RetryPolicy())
init(apiKey: String, apiRevision: String = "2026-05-20", retryPolicy: RetryPolicy? = RetryPolicy(), session: URLSession)
```

- Default: `RetryPolicy()` (retry enabled with defaults).
- `nil`: Retry disabled entirely.

Store as `private let retryPolicy: RetryPolicy?`.

### execute() Retry Loop

Modify `execute(_:)` to wrap the `URLSession.data(for:)` call in a retry loop:

1. For each attempt (1 to `maxAttempts`):
   - Set `urlRequest.timeoutInterval` to `min(initialTimeout * pow(timeoutMultiplier, attempt - 1), maxTimeout)`.
   - Call `session.data(for: urlRequest)`.
   - On success (2xx): return data as before.
   - On `URLError.timedOut`: if attempts remain, call `onRetry`, sleep for backoff duration, continue.
   - On HTTP status in `retryableStatusCodes`: if attempts remain, call `onRetry`, sleep, continue. For 429, respect `Retry-After` header if present (use it instead of calculated backoff).
   - On other errors: throw immediately (not retryable).
2. After all attempts exhausted: throw the last error.
3. Backoff calculation: `initialBackoff * pow(backoffMultiplier, attempt - 1)`.

When `retryPolicy` is `nil`, behave exactly as today (single attempt, no timeout adjustment).

### executeReturningResponse() 

Must also use the same retry logic. Both methods share the retry loop — extract a common private helper.

### Remove RequestTimeout

Remove the `RequestTimeout` config parameter type entirely. `RetryPolicy` subsumes its functionality via `initialTimeout`.

## Constraints

- `RetryPolicy` and `RetryEvent` must be `Sendable`.
- `InteractionsClient` remains an `actor`.
- All new types are `public`.
- No changes to existing public API signatures other than adding `retryPolicy` parameter to init.

## File Organization

All changes in `Sources/SwiftGeminiInteractions/Core.swift`. No new files.

## Testing Strategy

Tests in `Tests/SwiftGeminiInteractionsTests/` using `MockURLProtocol`:

- Retry on 429: mock 429 then 200, verify success after retry
- Retry on 503: mock 503 then 200, verify success after retry
- Retry respects Retry-After header: mock 429 with Retry-After header, verify backoff duration
- Retry on URLError.timedOut: mock timeout then 200, verify success after retry
- Non-retryable error throws immediately: mock 400, verify no retry
- Max attempts exhausted: mock 3x 503, verify final error thrown
- onRetry callback is called: mock retryable error, verify callback receives correct RetryEvent
- nil retryPolicy disables retry: mock 503, verify single attempt
- Timeout grows per attempt: verify URLRequest.timeoutInterval increases
