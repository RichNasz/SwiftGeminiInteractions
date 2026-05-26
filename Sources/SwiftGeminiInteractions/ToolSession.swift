// Sources/SwiftGeminiInteractions/ToolSession.swift
import Foundation

#if ToolSession

// MARK: - ToolCallLogEntry

public struct ToolCallLogEntry: Sendable {
    public let name: String
    public let arguments: String
    public let result: String
    public let duration: Duration

    public init(name: String, arguments: String, result: String, duration: Duration) {
        self.name = name
        self.arguments = arguments
        self.result = result
        self.duration = duration
    }
}

// MARK: - ToolSessionResult

public struct ToolSessionResult: Sendable {
    public let interaction: Interaction
    public let iterations: Int
    public let log: [ToolCallLogEntry]
    public let iterationUsages: [Usage]

    public init(interaction: Interaction, iterations: Int, log: [ToolCallLogEntry], iterationUsages: [Usage]) {
        self.interaction = interaction
        self.iterations = iterations
        self.log = log
        self.iterationUsages = iterationUsages
    }

    /// Sum of token usage across all iterations (avoids double-counting by summing all elements).
    public var totalUsage: Usage? {
        guard !iterationUsages.isEmpty else { return nil }
        return iterationUsages.dropFirst().reduce(into: iterationUsages[0]) { acc, usage in
            acc = Usage(
                totalInputTokens: acc.totalInputTokens + usage.totalInputTokens,
                totalOutputTokens: acc.totalOutputTokens + usage.totalOutputTokens,
                totalThoughtTokens: acc.totalThoughtTokens + usage.totalThoughtTokens,
                totalCachedTokens: acc.totalCachedTokens + usage.totalCachedTokens,
                totalToolUseTokens: acc.totalToolUseTokens + usage.totalToolUseTokens,
                totalTokens: acc.totalTokens + usage.totalTokens,
                // inputTokensByModality is taken from the final iteration — per-iteration modality
                // data is not additive across turns.
                inputTokensByModality: usage.inputTokensByModality
            )
        }
    }
}

// MARK: - ToolSessionEvent

public enum ToolSessionEvent: Sendable {
    case iterationStarted(Int)
    case llm(InteractionStreamEvent)
    case toolCallStarted(callId: String, name: String, arguments: String)
    case toolCallCompleted(callId: String, name: String, output: String, duration: Duration)
    case usageUpdate(Usage, iteration: Int)
}

// MARK: - ToolSession

public struct ToolSession: Sendable {
    public typealias ToolHandler = @Sendable (String) async throws -> String

    private let client: InteractionsClient
    private let tools: [InteractionTool]
    private let handlers: [String: ToolHandler]
    private let maxIterations: Int

    public init(
        client: InteractionsClient,
        tools: [InteractionTool],
        handlers: [String: ToolHandler],
        maxIterations: Int = 10
    ) {
        self.client = client
        self.tools = tools
        self.handlers = handlers
        self.maxIterations = maxIterations
    }

    /// Run the tool-calling loop: send → check status → execute function calls in parallel → chain.
    public func run(
        model: String,
        input: [Step],
        configParams: [any InteractionConfigParameter]
    ) async throws -> ToolSessionResult {
        var iterations = 0
        var log: [ToolCallLogEntry] = []
        var iterationUsages: [Usage] = []
        var previousId: String? = nil
        var currentInput = input

        while true {
            guard iterations < maxIterations else {
                throw GeminiInteractionsError.maxIterationsExceeded(maxIterations)
            }

            let request = buildRequest(
                model: model,
                input: currentInput,
                previousId: previousId,
                configParams: configParams
            )

            let interaction = try await client.send(request)
            iterations += 1

            if let usage = interaction.usage {
                iterationUsages.append(usage)
            }

            // If not requires_action, we're done
            guard interaction.status == .requiresAction else {
                return ToolSessionResult(
                    interaction: interaction,
                    iterations: iterations,
                    log: log,
                    iterationUsages: iterationUsages
                )
            }

            // Collect all function calls from the interaction
            let functionCalls: [(id: String, name: String, arguments: String)] = interaction.steps.compactMap { step in
                if case .functionCall(let id, let name, let arguments) = step {
                    return (id: id, name: name, arguments: arguments)
                }
                return nil
            }

            // Execute all handlers concurrently using a task group
            struct ToolResult {
                let callId: String
                let name: String
                let arguments: String
                let output: String
                let isError: Bool
                let duration: Duration
            }

            var toolResults: [ToolResult] = []

            try await withThrowingTaskGroup(of: ToolResult.self) { group in
                for call in functionCalls {
                    let handler = handlers[call.name]
                    let callId = call.id
                    let name = call.name
                    let arguments = call.arguments
                    group.addTask {
                        let clock = ContinuousClock()
                        let start = clock.now
                        let output: String
                        let isError: Bool
                        do {
                            if let h = handler {
                                output = try await h(arguments)
                                isError = false
                            } else {
                                // Error case: no handler was registered for this tool name.
                                output = "Error: No handler registered for tool '\(name)'"
                                isError = true
                            }
                        } catch {
                            output = "Error: \(String(describing: error))"
                            isError = true
                        }
                        let duration = clock.now - start
                        return ToolResult(callId: callId, name: name, arguments: arguments, output: output, isError: isError, duration: duration)
                    }
                }
                for try await result in group {
                    toolResults.append(result)
                }
            }

            // Append to log
            for result in toolResults {
                log.append(ToolCallLogEntry(
                    name: result.name,
                    arguments: result.arguments,
                    result: result.output,
                    duration: result.duration
                ))
            }

            // Build the next input: function results in the same order as function calls
            let orderedResults = functionCalls.compactMap { call in
                toolResults.first(where: { $0.callId == call.id })
            }
            currentInput = orderedResults.map { result in
                Step.functionResult(callId: result.callId, result: result.output, name: result.name, isError: result.isError)
            }

            previousId = interaction.id
        }
    }

    /// Stream the tool-calling loop: yields iteration/tool events and all SSE events from each LLM call.
    public func stream(
        model: String,
        input: [Step],
        configParams: [any InteractionConfigParameter]
    ) -> AsyncThrowingStream<ToolSessionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var currentInput = input
                    var currentPreviousId: String? = nil
                    var iteration = 0

                    while iteration < maxIterations {
                        iteration += 1
                        continuation.yield(.iterationStarted(iteration))

                        let request = buildRequest(
                            model: model,
                            input: currentInput,
                            previousId: currentPreviousId,
                            configParams: configParams
                        )

                        // Forward all SSE events; collect the completed interaction
                        var completedInteraction: Interaction? = nil
                        for try await event in client.stream(request) {
                            continuation.yield(.llm(event))
                            if case .interactionCompleted(let interaction) = event {
                                completedInteraction = interaction
                                if let usage = interaction.usage {
                                    continuation.yield(.usageUpdate(usage, iteration: iteration))
                                }
                            }
                        }

                        guard let interaction = completedInteraction else { break }

                        // Collect function calls from the completed interaction's steps
                        let functionCalls: [(index: Int, id: String, name: String, arguments: String)] = interaction.steps
                            .enumerated()
                            .compactMap { (idx, step) in
                                if case .functionCall(let id, let name, let args) = step {
                                    return (index: idx, id: id, name: name, arguments: args)
                                }
                                return nil
                            }

                        // If terminal status or no function calls, we're done
                        if functionCalls.isEmpty || interaction.isComplete {
                            continuation.finish()
                            return
                        }

                        // Execute handlers in parallel
                        struct StreamToolResult {
                            let index: Int
                            let callId: String
                            let name: String
                            let output: String
                            let isError: Bool
                            let duration: Duration
                        }

                        let results: [StreamToolResult] = try await withThrowingTaskGroup(of: StreamToolResult.self) { group in
                            for call in functionCalls {
                                let handler = handlers[call.name]
                                group.addTask {
                                    continuation.yield(.toolCallStarted(callId: call.id, name: call.name, arguments: call.arguments))
                                    let clock = ContinuousClock()
                                    let start = clock.now
                                    let output: String
                                    let isError: Bool
                                    if let handler {
                                        do {
                                            output = try await handler(call.arguments)
                                            isError = false
                                        } catch {
                                            output = "Error: \(String(describing: error))"
                                            isError = true
                                        }
                                    } else {
                                        output = "Error: No handler registered for tool '\(call.name)'"
                                        isError = true
                                    }
                                    let duration = clock.now - start
                                    continuation.yield(.toolCallCompleted(callId: call.id, name: call.name, output: output, duration: duration))
                                    return StreamToolResult(index: call.index, callId: call.id, name: call.name, output: output, isError: isError, duration: duration)
                                }
                            }
                            var collected: [StreamToolResult] = []
                            for try await r in group { collected.append(r) }
                            return collected.sorted { $0.index < $1.index }
                        }

                        // Build next input from function results in original order
                        currentInput = results.map { r in
                            Step.functionResult(callId: r.callId, result: r.output, name: r.name, isError: r.isError)
                        }
                        currentPreviousId = interaction.id
                    }

                    throw GeminiInteractionsError.maxIterationsExceeded(maxIterations)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private helpers

    private func buildRequest(
        model: String,
        input: [Step],
        previousId: String?,
        configParams: [any InteractionConfigParameter]
    ) -> InteractionRequest {
        var request = InteractionRequest(input: .steps(input))
        request.model = model
        request.tools = tools.isEmpty ? nil : tools
        request.previousInteractionId = previousId

        for param in configParams {
            param.apply(to: &request)
        }

        request.store = true
        return request
    }
}

#endif
