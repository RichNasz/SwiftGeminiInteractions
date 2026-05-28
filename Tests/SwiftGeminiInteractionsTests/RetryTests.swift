import Testing
import Foundation
@testable import SwiftGeminiInteractions

/// Thread-safe collector for RetryEvent values captured in @Sendable onRetry closures.
private final class RetryEventCollector: @unchecked Sendable {
    private var _events: [RetryEvent] = []
    private let lock = NSLock()

    func append(_ event: RetryEvent) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(event)
    }

    var events: [RetryEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }
}

@Suite(.serialized)
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

    @Test func clientDefaultRetryPolicy() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON())
        }
        let client = makeTestClient()
        let interaction = try await client.send(InteractionRequest(input: .text("test")))
        #expect(interaction.id == "v1_test")
    }

    @Test func clientNilRetryPolicyDisablesRetry() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, makeInteractionJSON())
        }
        let client = makeTestClient(retryPolicy: nil)
        let interaction = try await client.send(InteractionRequest(input: .text("test")))
        #expect(interaction.id == "v1_test")
    }

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

    @Test func retryRespectsRetryAfterHeader() async throws {
        var callCount = 0
        let collector = RetryEventCollector()
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
            onRetry: { event in collector.append(event) }
        ))
        let interaction = try await client.send(InteractionRequest(input: .text("test")))
        #expect(interaction.id == "v1_test")
        #expect(collector.events.count == 1)
        #expect(collector.events[0].backoffDuration == .seconds(5))
    }

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

    @Test func onRetryCallbackReceivesCorrectEvents() async throws {
        var callCount = 0
        let collector = RetryEventCollector()
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
            onRetry: { event in collector.append(event) }
        ))
        let interaction = try await client.send(InteractionRequest(input: .text("test")))
        #expect(interaction.id == "v1_test")
        let retryEvents = collector.events
        #expect(retryEvents.count == 2)
        #expect(retryEvents[0].attempt == 1)
        #expect(retryEvents[0].maxAttempts == 3)
        #expect(retryEvents[0].backoffDuration == .milliseconds(10))
        #expect(retryEvents[1].attempt == 2)
        #expect(retryEvents[1].backoffDuration == .milliseconds(20))
    }

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
        #expect(capturedTimeouts[2] == 30.0)
    }
}
