# Retry-with-Backoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic retry with exponential backoff to `InteractionsClient` for transient errors (429, 500, 503, timeout).

**Architecture:** New `RetryPolicy` and `RetryEvent` types in Core.swift. A private retry helper method wraps the `session.data(for:)` call and is used by both `execute()` and `executeReturningResponse()`. `RequestTimeout` parameter type is removed.

**Tech Stack:** Swift 6.3, Foundation (`URLSession`, `Duration`, `Task.sleep`)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/SwiftGeminiInteractions/Core.swift` | Modify | Add `RetryPolicy`, `RetryEvent` types; add `retryPolicy` stored property and init parameter; extract private retry helper; update `execute()` and `executeReturningResponse()`; remove `RequestTimeout` |
| `Tests/SwiftGeminiInteractionsTests/RetryTests.swift` | Create | All retry-related tests |
| `Tests/SwiftGeminiInteractionsTests/MockURLProtocol.swift` | Modify | Update `makeTestClient` to accept `retryPolicy` parameter |

---

### Task 1: Add RetryPolicy and RetryEvent types

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/Core.swift`
- Create: `Tests/SwiftGeminiInteractionsTests/RetryTests.swift`

- [ ] **Step 1: Write the test file with default-values test**

Create `Tests/SwiftGeminiInteractionsTests/RetryTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftGeminiInteractions

struct RetryTests {
    @Test func retryPolicyDefaultValues() {
        let policy = RetryPolicy()
        #expect(policy.maxAttempts == 3)
        #expect(policy.initialBackoff == .seconds(2))
        #expect(policy.backoffMultiplier == 2.0)
        #expect(policy.initialTimeout == .seconds(120))
        #expect(policy.timeoutMultiplier == 1.5)
        #expect(policy.maxTimeout == .seconds(300))
        #expect(policy.retryableStatusCodes == [429, 500, 503])
        #expect(policy.onRetry == nil)
    }

    @Test func retryPolicyCustomValues() {
        let policy = RetryPolicy(
            maxAttempts: 5,
            initialBackoff: .seconds(1),
            backoffMultiplier: 3.0,
            initialTimeout: .seconds(60),
            timeoutMultiplier: 2.0,
            maxTimeout: .seconds(600),
            retryableStatusCodes: [429, 502, 503]
        )
        #expect(policy.maxAttempts == 5)
        #expect(policy.initialBackoff == .seconds(1))
        #expect(policy.backoffMultiplier == 3.0)
        #expect(policy.initialTimeout == .seconds(60))
        #expect(policy.timeoutMultiplier == 2.0)
        #expect(policy.maxTimeout == .seconds(600))
        #expect(policy.retryableStatusCodes == [429, 502, 503])
    }

    @Test func retryEventProperties() {
        let event = RetryEvent(
            attempt: 1,
            maxAttempts: 3,
            error: .rateLimitExceeded,
            backoffDuration: .seconds(2),
            nextTimeout: .seconds(180)
        )
        #expect(event.attempt == 1)
        #expect(event.maxAttempts == 3)
        #expect(event.backoffDuration == .seconds(2))
        #expect(event.nextTimeout == .seconds(180))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RetryTests 2>&1 | tail -20`
Expected: FAIL — `RetryPolicy` and `RetryEvent` not defined.

- [ ] **Step 3: Add RetryPolicy and RetryEvent to Core.swift**

Add these types just before the `// MARK: - InteractionsClient` section (after the result builders, before the actor):

```swift
// MARK: - Retry

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let initialBackoff: Duration
    public let backoffMultiplier: Double
    public let initialTimeout: Duration
    public let timeoutMultiplier: Double
    public let maxTimeout: Duration
    public let retryableStatusCodes: Set<Int>
    public let onRetry: (@Sendable (RetryEvent) -> Void)?

    public init(
        maxAttempts: Int = 3,
        initialBackoff: Duration = .seconds(2),
        backoffMultiplier: Double = 2.0,
        initialTimeout: Duration = .seconds(120),
        timeoutMultiplier: Double = 1.5,
        maxTimeout: Duration = .seconds(300),
        retryableStatusCodes: Set<Int> = [429, 500, 503],
        onRetry: (@Sendable (RetryEvent) -> Void)? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.initialBackoff = initialBackoff
        self.backoffMultiplier = backoffMultiplier
        self.initialTimeout = initialTimeout
        self.timeoutMultiplier = timeoutMultiplier
        self.maxTimeout = maxTimeout
        self.retryableStatusCodes = retryableStatusCodes
        self.onRetry = onRetry
    }
}

public struct RetryEvent: Sendable {
    public let attempt: Int
    public let maxAttempts: Int
    public let error: GeminiInteractionsError
    public let backoffDuration: Duration
    public let nextTimeout: Duration

    public init(
        attempt: Int,
        maxAttempts: Int,
        error: GeminiInteractionsError,
        backoffDuration: Duration,
        nextTimeout: Duration
    ) {
        self.attempt = attempt
        self.maxAttempts = maxAttempts
        self.error = error
        self.backoffDuration = backoffDuration
        self.nextTimeout = nextTimeout
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RetryTests 2>&1 | tail -20`
Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftGeminiInteractions/Core.swift Tests/SwiftGeminiInteractionsTests/RetryTests.swift
git commit -m "feat: add RetryPolicy and RetryEvent types"
```

---

### Task 2: Add retryPolicy to InteractionsClient init and remove RequestTimeout

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/Core.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/MockURLProtocol.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/RetryTests.swift`

- [ ] **Step 1: Write tests for init with retryPolicy**

Add to `RetryTests.swift`:

```swift
@Test func clientDefaultRetryPolicy() async {
    let client = makeTestClient()
    // Client should work with default retry policy — verify by making a successful request
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON())
    }
    let interaction = try await client.send(InteractionRequest(input: .text("test")))
    #expect(interaction.id == "v1_test")
}

@Test func clientNilRetryPolicyDisablesRetry() async {
    let client = makeTestClient(retryPolicy: nil)
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON())
    }
    let interaction = try await client.send(InteractionRequest(input: .text("test")))
    #expect(interaction.id == "v1_test")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RetryTests 2>&1 | tail -20`
Expected: FAIL — `makeTestClient` does not accept `retryPolicy`.

- [ ] **Step 3: Update makeTestClient to accept retryPolicy**

In `Tests/SwiftGeminiInteractionsTests/MockURLProtocol.swift`, change `makeTestClient`:

```swift
func makeTestClient(apiKey: String = "test-key", apiRevision: String = "2026-05-20", retryPolicy: RetryPolicy? = RetryPolicy()) -> InteractionsClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return InteractionsClient(apiKey: apiKey, apiRevision: apiRevision, retryPolicy: retryPolicy, session: session)
}
```

- [ ] **Step 4: Add retryPolicy to InteractionsClient**

In Core.swift, add `private let retryPolicy: RetryPolicy?` to the actor's stored properties and update both initializers:

```swift
public actor InteractionsClient {
    private let apiKey: String
    private let apiRevision: String
    let session: URLSession
    let baseURL: URL
    private let retryPolicy: RetryPolicy?

    public init(apiKey: String, apiRevision: String = "2026-05-20", retryPolicy: RetryPolicy? = RetryPolicy()) {
        self.apiKey = apiKey
        self.apiRevision = apiRevision
        self.retryPolicy = retryPolicy
        self.session = URLSession.shared
        self.baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    }

    init(apiKey: String, apiRevision: String = "2026-05-20", retryPolicy: RetryPolicy? = RetryPolicy(), session: URLSession) {
        self.apiKey = apiKey
        self.apiRevision = apiRevision
        self.retryPolicy = retryPolicy
        self.session = session
        self.baseURL = URL(string: "https://generativelanguage.googleapis.com")!
    }
```

- [ ] **Step 5: Remove RequestTimeout**

Delete the `RequestTimeout` struct from Core.swift (lines around 1469-1474):

```swift
// DELETE THIS:
public struct RequestTimeout: InteractionConfigParameter {
    /// The timeout interval in seconds.
    public let value: TimeInterval
    public init(_ value: TimeInterval) { self.value = value }
    public func apply(to request: inout InteractionRequest) { /* consumed by client */ }
}
```

- [ ] **Step 6: Run ALL tests to verify nothing breaks**

Run: `swift test 2>&1 | tail -20`
Expected: All tests PASS. No existing code references `RequestTimeout`.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftGeminiInteractions/Core.swift Tests/SwiftGeminiInteractionsTests/MockURLProtocol.swift Tests/SwiftGeminiInteractionsTests/RetryTests.swift
git commit -m "feat: add retryPolicy to InteractionsClient init, remove RequestTimeout"
```

---

### Task 3: Implement retry logic in execute() and executeReturningResponse()

**Files:**
- Modify: `Sources/SwiftGeminiInteractions/Core.swift`
- Modify: `Tests/SwiftGeminiInteractionsTests/RetryTests.swift`

- [ ] **Step 1: Write test for retry on 503**

Add to `RetryTests.swift`:

```swift
@Test func retryOn503ThenSuccess() async throws {
    var callCount = 0
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        if callCount == 1 {
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON())
    }

    let client = makeTestClient(retryPolicy: RetryPolicy(initialBackoff: .milliseconds(10)))
    let interaction = try await client.send(InteractionRequest(input: .text("test")))
    #expect(interaction.id == "v1_test")
    #expect(callCount == 2)
}
```

- [ ] **Step 2: Write test for retry on 429**

```swift
@Test func retryOn429ThenSuccess() async throws {
    var callCount = 0
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        if callCount == 1 {
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON())
    }

    let client = makeTestClient(retryPolicy: RetryPolicy(initialBackoff: .milliseconds(10)))
    let interaction = try await client.send(InteractionRequest(input: .text("test")))
    #expect(interaction.id == "v1_test")
    #expect(callCount == 2)
}
```

- [ ] **Step 3: Write test for 429 with Retry-After header**

```swift
@Test func retryRespectsRetryAfterHeader() async throws {
    var callCount = 0
    var retryEvents: [RetryEvent] = []
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        if callCount == 1 {
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "5"])!
            return (response, Data())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON())
    }

    let client = makeTestClient(retryPolicy: RetryPolicy(
        initialBackoff: .milliseconds(10),
        onRetry: { event in retryEvents.append(event) }
    ))
    let interaction = try await client.send(InteractionRequest(input: .text("test")))
    #expect(interaction.id == "v1_test")
    #expect(retryEvents.count == 1)
    #expect(retryEvents[0].backoffDuration == .seconds(5))
}
```

- [ ] **Step 4: Write test for non-retryable error**

```swift
@Test func nonRetryableErrorThrowsImmediately() async throws {
    var callCount = 0
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
        return (response, "Bad request".data(using: .utf8)!)
    }

    let client = makeTestClient(retryPolicy: RetryPolicy(initialBackoff: .milliseconds(10)))
    do {
        _ = try await client.send(InteractionRequest(input: .text("test")))
        Issue.record("Expected error")
    } catch let error as GeminiInteractionsError {
        guard case .httpError(let statusCode, _) = error else {
            Issue.record("Expected httpError, got \(error)")
            return
        }
        #expect(statusCode == 400)
    }
    #expect(callCount == 1)
}
```

- [ ] **Step 5: Write test for max attempts exhausted**

```swift
@Test func maxAttemptsExhaustedThrowsLastError() async throws {
    var callCount = 0
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        return (response, "Service unavailable".data(using: .utf8)!)
    }

    let client = makeTestClient(retryPolicy: RetryPolicy(
        maxAttempts: 3,
        initialBackoff: .milliseconds(10)
    ))
    do {
        _ = try await client.send(InteractionRequest(input: .text("test")))
        Issue.record("Expected error")
    } catch let error as GeminiInteractionsError {
        guard case .httpError(let statusCode, _) = error else {
            Issue.record("Expected httpError, got \(error)")
            return
        }
        #expect(statusCode == 503)
    }
    #expect(callCount == 3)
}
```

- [ ] **Step 6: Write test for onRetry callback**

```swift
@Test func onRetryCallbackReceivesCorrectEvents() async throws {
    var callCount = 0
    var retryEvents: [RetryEvent] = []
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        if callCount <= 2 {
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON())
    }

    let client = makeTestClient(retryPolicy: RetryPolicy(
        maxAttempts: 3,
        initialBackoff: .milliseconds(10),
        backoffMultiplier: 2.0,
        onRetry: { event in retryEvents.append(event) }
    ))
    let interaction = try await client.send(InteractionRequest(input: .text("test")))
    #expect(interaction.id == "v1_test")
    #expect(retryEvents.count == 2)
    #expect(retryEvents[0].attempt == 1)
    #expect(retryEvents[0].maxAttempts == 3)
    #expect(retryEvents[0].backoffDuration == .milliseconds(10))
    #expect(retryEvents[1].attempt == 2)
    #expect(retryEvents[1].backoffDuration == .milliseconds(20))
}
```

- [ ] **Step 7: Write test for nil retryPolicy makes single attempt**

```swift
@Test func nilRetryPolicySingleAttemptOn503() async throws {
    var callCount = 0
    MockURLProtocol.requestHandler = { request in
        callCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        return (response, "Service unavailable".data(using: .utf8)!)
    }

    let client = makeTestClient(retryPolicy: nil)
    do {
        _ = try await client.send(InteractionRequest(input: .text("test")))
        Issue.record("Expected error")
    } catch let error as GeminiInteractionsError {
        guard case .httpError(let statusCode, _) = error else {
            Issue.record("Expected httpError, got \(error)")
            return
        }
        #expect(statusCode == 503)
    }
    #expect(callCount == 1)
}
```

- [ ] **Step 8: Write test for timeout grows per attempt**

```swift
@Test func timeoutGrowsPerAttempt() async throws {
    var capturedTimeouts: [TimeInterval] = []
    var callCount = 0
    MockURLProtocol.requestHandler = { request in
        capturedTimeouts.append(request.timeoutInterval)
        callCount += 1
        if callCount <= 2 {
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (response, makeInteractionJSON())
    }

    let client = makeTestClient(retryPolicy: RetryPolicy(
        maxAttempts: 3,
        initialBackoff: .milliseconds(10),
        initialTimeout: .seconds(10),
        timeoutMultiplier: 2.0,
        maxTimeout: .seconds(30)
    ))
    _ = try await client.send(InteractionRequest(input: .text("test")))
    #expect(capturedTimeouts.count == 3)
    #expect(capturedTimeouts[0] == 10.0)
    #expect(capturedTimeouts[1] == 20.0)
    #expect(capturedTimeouts[2] == 30.0) // capped at maxTimeout
}
```

- [ ] **Step 9: Run tests to verify they fail**

Run: `swift test --filter RetryTests 2>&1 | tail -30`
Expected: FAIL — retry logic not yet implemented.

- [ ] **Step 10: Implement the retry logic**

In Core.swift, add a private retry helper and refactor `execute()` and `executeReturningResponse()` to use it.

Add this private method to `InteractionsClient`:

```swift
private func performRequest(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard let policy = retryPolicy else {
        return try await singleAttempt(urlRequest)
    }

    var lastError: GeminiInteractionsError?
    for attempt in 1...policy.maxAttempts {
        var request = urlRequest
        let timeoutSeconds = min(
            Double(policy.initialTimeout.components.seconds) * pow(policy.timeoutMultiplier, Double(attempt - 1)),
            Double(policy.maxTimeout.components.seconds)
        )
        request.timeoutInterval = timeoutSeconds

        do {
            return try await singleAttempt(request)
        } catch let error as GeminiInteractionsError {
            let isRetryable: Bool
            var retryAfterDuration: Duration?
            switch error {
            case .networkError(let urlError) where urlError.code == .timedOut:
                isRetryable = true
            case .rateLimitExceeded:
                isRetryable = policy.retryableStatusCodes.contains(429)
            case .httpError(let statusCode, _):
                isRetryable = policy.retryableStatusCodes.contains(statusCode)
            default:
                isRetryable = false
            }

            lastError = error
            guard isRetryable && attempt < policy.maxAttempts else { throw error }

            let backoff: Duration
            if case .rateLimitExceeded = error, let retryAfter = retryAfterDuration {
                backoff = retryAfter
            } else {
                backoff = policy.initialBackoff * Int(pow(policy.backoffMultiplier, Double(attempt - 1)))
            }

            let nextTimeoutSeconds = min(
                Double(policy.initialTimeout.components.seconds) * pow(policy.timeoutMultiplier, Double(attempt)),
                Double(policy.maxTimeout.components.seconds)
            )

            policy.onRetry?(RetryEvent(
                attempt: attempt,
                maxAttempts: policy.maxAttempts,
                error: error,
                backoffDuration: backoff,
                nextTimeout: .seconds(Int64(nextTimeoutSeconds))
            ))

            try await Task.sleep(for: backoff)
        }
    }
    throw lastError!
}
```

**Important:** The above needs adjustment for 429 Retry-After handling. The `retryAfterDuration` must be extracted from the HTTP response headers. Since `execute()` currently handles HTTP status codes, the retry helper needs to work at the `session.data(for:)` level, before status code processing.

The actual implementation should restructure the flow:

```swift
private func performRequest(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    guard let policy = retryPolicy else {
        return try await singleAttempt(urlRequest)
    }

    var lastError: GeminiInteractionsError!
    for attempt in 1...policy.maxAttempts {
        var request = urlRequest
        let timeoutSeconds = min(
            Double(policy.initialTimeout.components.seconds) * pow(policy.timeoutMultiplier, Double(attempt - 1)),
            Double(policy.maxTimeout.components.seconds)
        )
        request.timeoutInterval = timeoutSeconds

        let isRetryable: Bool
        var backoffOverride: Duration?

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiInteractionsError.httpError(statusCode: 0, body: "No HTTP response")
            }
            switch httpResponse.statusCode {
            case 200...299:
                return (data, httpResponse)
            case _ where policy.retryableStatusCodes.contains(httpResponse.statusCode):
                if httpResponse.statusCode == 429,
                   let retryAfterStr = httpResponse.value(forHTTPHeaderField: "Retry-After"),
                   let retryAfterSec = Int64(retryAfterStr) {
                    backoffOverride = .seconds(retryAfterSec)
                }
                let body = String(data: data, encoding: .utf8) ?? ""
                if httpResponse.statusCode == 429 {
                    lastError = .rateLimitExceeded
                } else {
                    lastError = .httpError(statusCode: httpResponse.statusCode, body: body)
                }
                isRetryable = true
            case 429:
                throw GeminiInteractionsError.rateLimitExceeded
            default:
                let body = String(data: data, encoding: .utf8) ?? ""
                throw GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: body)
            }
        } catch let urlError as URLError where urlError.code == .timedOut {
            lastError = .networkError(urlError)
            isRetryable = true
        } catch let error as GeminiInteractionsError {
            throw error
        } catch {
            throw error
        }

        guard isRetryable && attempt < policy.maxAttempts else {
            throw lastError!
        }

        let backoff = backoffOverride ?? policy.initialBackoff * Int(pow(policy.backoffMultiplier, Double(attempt - 1)))

        let nextTimeoutSeconds = min(
            Double(policy.initialTimeout.components.seconds) * pow(policy.timeoutMultiplier, Double(attempt)),
            Double(policy.maxTimeout.components.seconds)
        )

        policy.onRetry?(RetryEvent(
            attempt: attempt,
            maxAttempts: policy.maxAttempts,
            error: lastError,
            backoffDuration: backoff,
            nextTimeout: .seconds(Int64(nextTimeoutSeconds))
        ))

        try await Task.sleep(for: backoff)
    }
    throw lastError!
}

private func singleAttempt(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response): (Data, URLResponse)
    do {
        (data, response) = try await session.data(for: urlRequest)
    } catch let urlError as URLError {
        throw GeminiInteractionsError.networkError(urlError)
    }
    guard let httpResponse = response as? HTTPURLResponse else {
        throw GeminiInteractionsError.httpError(statusCode: 0, body: "No HTTP response")
    }
    switch httpResponse.statusCode {
    case 200...299:
        return (data, httpResponse)
    case 429:
        throw GeminiInteractionsError.rateLimitExceeded
    default:
        let body = String(data: data, encoding: .utf8) ?? ""
        throw GeminiInteractionsError.httpError(statusCode: httpResponse.statusCode, body: body)
    }
}
```

Then refactor `execute()` and `executeReturningResponse()`:

```swift
func execute(_ urlRequest: URLRequest) async throws -> Data {
    let (data, _) = try await performRequest(urlRequest)
    return data
}

func executeReturningResponse(_ urlRequest: URLRequest) async throws -> (Data, HTTPURLResponse) {
    return try await performRequest(urlRequest)
}
```

- [ ] **Step 11: Run tests to verify they pass**

Run: `swift test --filter RetryTests 2>&1 | tail -30`
Expected: All tests PASS.

- [ ] **Step 12: Run ALL tests to verify no regressions**

Run: `swift test 2>&1 | tail -30`
Expected: All tests PASS.

- [ ] **Step 13: Commit**

```bash
git add Sources/SwiftGeminiInteractions/Core.swift Tests/SwiftGeminiInteractionsTests/RetryTests.swift
git commit -m "feat: implement retry-with-backoff in execute() and executeReturningResponse()"
```

---

### Task 4: Update documentation and CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-05-27-retry-with-backoff-design.md`

- [ ] **Step 1: Update design spec status to Implemented**

Change `**Status:** Approved` to `**Status:** Implemented`.

- [ ] **Step 2: Update CLAUDE.md**

No file map changes needed (all changes are in Core.swift). Update the "Key Design Decisions" section to mention retry:

Add a new subsection under "Key Design Decisions":

```markdown
### Retry with Backoff
`InteractionsClient` accepts an optional `RetryPolicy` at init time. When enabled (default), transient errors (429, 500, 503, timeout) are retried with exponential backoff. The retry logic is in a private `performRequest()` helper shared by `execute()` and `executeReturningResponse()`. `RequestTimeout` was removed — `RetryPolicy.initialTimeout` replaces it.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-05-27-retry-with-backoff-design.md
git commit -m "docs: update CLAUDE.md and design spec for retry-with-backoff"
```
