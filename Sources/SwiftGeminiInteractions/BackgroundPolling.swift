// Sources/SwiftGeminiInteractions/BackgroundPolling.swift
import Foundation

// MARK: - poll

extension InteractionsClient {
    /// Polls a stored interaction until it reaches a terminal status.
    ///
    /// Calls ``get(id:)`` in a loop, sleeping for `interval` between checks.
    /// Throws ``GeminiInteractionsError/pollTimeout(id:)`` if `timeout` is exceeded.
    ///
    /// - Parameters:
    ///   - id: The interaction ID to poll.
    ///   - timeout: Maximum wait time (default: 300 seconds).
    ///   - interval: Time between poll attempts (default: 5 seconds).
    /// - Returns: The completed interaction.
    public func poll(
        id: String,
        timeout: Duration = .seconds(300),
        interval: Duration = .seconds(5)
    ) async throws -> Interaction {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            let interaction = try await get(id: id)
            if interaction.isComplete { return interaction }
            let remaining = deadline - clock.now
            if remaining > .zero {
                try await Task.sleep(for: min(interval, remaining))
            }
        }
        throw GeminiInteractionsError.pollTimeout(id: id)
    }
}
