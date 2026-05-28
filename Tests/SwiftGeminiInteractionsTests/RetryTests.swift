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
