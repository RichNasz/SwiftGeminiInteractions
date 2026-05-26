// Sources/SwiftGeminiInteractions/BackgroundPolling.swift
import Foundation

// MARK: - poll

extension InteractionsClient {
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
