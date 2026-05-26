// Sources/SwiftGeminiInteractions/Agent.swift
import Foundation

#if Agent

// MARK: - AgentTool

/// Pairs an ``InteractionTool`` with a handler closure for use with ``Agent``.
public struct AgentTool: Sendable {
    /// The tool definition sent to the API.
    public let tool: InteractionTool
    /// The closure that executes when the model calls this tool.
    public let handler: ToolSession.ToolHandler

    /// Creates an `AgentTool` from a tool definition and handler closure.
    public init(tool: InteractionTool, handler: @escaping ToolSession.ToolHandler) {
        self.tool = tool
        self.handler = handler
    }

    /// Creates an `AgentTool` from an `@LLMTool`-conforming type, extracting the tool definition and wrapping the `call` method as a handler.
    public init<T: LLMTool>(_ instance: T) {
        self.tool = InteractionTool(T.toolDefinition)
        self.handler = { args in
            guard let data = args.data(using: .utf8) else {
                throw GeminiInteractionsError.invalidInput("Cannot decode arguments as UTF-8")
            }
            let arguments = try JSONDecoder().decode(T.Arguments.self, from: data)
            let output = try await instance.call(arguments: arguments)
            return output.content
        }
    }
}

// MARK: - AgentToolBuilder

/// Result builder for composing `[AgentTool]` arrays in ``Agent`` initializers.
@resultBuilder
public struct AgentToolBuilder {
    public static func buildBlock(_ components: [AgentTool]...) -> [AgentTool] {
        components.flatMap { $0 }
    }
    public static func buildExpression(_ expression: AgentTool) -> [AgentTool] {
        [expression]
    }
    public static func buildOptional(_ component: [AgentTool]?) -> [AgentTool] {
        component ?? []
    }
    public static func buildEither(first component: [AgentTool]) -> [AgentTool] { component }
    public static func buildEither(second component: [AgentTool]) -> [AgentTool] { component }
    public static func buildArray(_ components: [[AgentTool]]) -> [AgentTool] {
        components.flatMap { $0 }
    }
}

// MARK: - TranscriptEntry

/// A log entry in an ``Agent``'s conversation transcript.
public enum TranscriptEntry: Sendable {
    /// A message sent by the user.
    case userMessage(String)
    /// A text response from the model.
    case assistantMessage(String)
    /// A model reasoning/thought step.
    case thought(String)
    /// A function tool call issued by the model.
    case toolCall(name: String, arguments: String)
    /// The result returned by a tool handler.
    case toolResult(name: String, result: String, duration: Duration)
    /// A server-side built-in tool invocation.
    case builtInToolCall(type: String)
    /// An error that occurred during the conversation.
    case error(String)
}

// MARK: - Agent

private enum ModelIdentifier: Sendable {
    case model(String)
    case agent(String)
}

/// A multi-turn conversational agent that wraps ``ToolSession`` with automatic interaction chaining, transcript tracking, and usage aggregation.
///
/// Use ``send(_:)`` for synchronous requests or ``stream(_:)`` for real-time event streaming.
/// Both automatically chain interactions via `previousInteractionId`.
public actor Agent {
    private let client: InteractionsClient
    private let modelIdentifier: ModelIdentifier
    private let instructions: String?
    private let agentTools: [AgentTool]
    private let configParams: [any InteractionConfigParameter]
    private let maxToolIterations: Int

    private var _lastInteractionId: String?
    private var _lastUsage: Usage?
    private var _transcript: [TranscriptEntry] = []

    /// The ID of the most recent interaction in the chain.
    public var lastInteractionId: String? { _lastInteractionId }
    /// Token usage from the most recent interaction.
    public var lastUsage: Usage? { _lastUsage }
    /// The full conversation transcript.
    public var transcript: [TranscriptEntry] { _transcript }

    // MARK: - Initializers

    /// Model-based initializer: sends requests with the specified model string.
    public init(
        client: InteractionsClient,
        model: String,
        instructions: String? = nil,
        maxToolIterations: Int = 10,
        @AgentToolBuilder tools: () -> [AgentTool] = { [] },
        @InteractionConfigBuilder config: () -> [any InteractionConfigParameter] = { [] }
    ) throws {
        self.client = client
        self.modelIdentifier = .model(model)
        self.instructions = instructions
        self.maxToolIterations = maxToolIterations
        self.configParams = config()
        let builtTools = tools()
        try Self.validateToolNames(builtTools)
        self.agentTools = builtTools
    }

    /// Named-agent initializer: sends requests targeting a named Gemini agent.
    public init(
        client: InteractionsClient,
        agent: String,
        instructions: String? = nil,
        maxToolIterations: Int = 10,
        @AgentToolBuilder tools: () -> [AgentTool] = { [] },
        @InteractionConfigBuilder config: () -> [any InteractionConfigParameter] = { [] }
    ) throws {
        self.client = client
        self.modelIdentifier = .agent(agent)
        self.instructions = instructions
        self.maxToolIterations = maxToolIterations
        self.configParams = config()
        let builtTools = tools()
        try Self.validateToolNames(builtTools)
        self.agentTools = builtTools
    }

    // MARK: - Public API

    /// Sends a message and returns the model's text output.
    ///
    /// Automatically chains to the previous interaction if one exists.
    ///
    /// - Parameter message: The user's message text.
    /// - Returns: The model's text response.
    public func send(_ message: String) async throws -> String {
        _transcript.append(.userMessage(message))
        let interaction: Interaction
        if agentTools.isEmpty {
            interaction = try await sendDirect(message: message)
        } else {
            interaction = try await sendWithTools(message: message)
        }
        _lastInteractionId = interaction.id
        _lastUsage = interaction.usage
        let output = interaction.outputText ?? ""
        _transcript.append(.assistantMessage(output))
        return output
    }

    /// Streams a message, yielding ``ToolSessionEvent`` values in real time.
    ///
    /// - Parameter message: The user's message text.
    /// - Returns: An async stream of events.
    public func stream(_ message: String) -> AsyncThrowingStream<ToolSessionEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    self._transcript.append(.userMessage(message))
                    if self.agentTools.isEmpty {
                        let request = self.buildDirectRequest(message: message)
                        var lastInteraction: Interaction? = nil
                        for try await event in self.client.stream(request) {
                            continuation.yield(.llm(event))
                            if case .interactionCompleted(let i) = event {
                                lastInteraction = i
                                if let usage = i.usage {
                                    continuation.yield(.usageUpdate(usage, iteration: 1))
                                }
                            }
                        }
                        if let interaction = lastInteraction {
                            self._lastInteractionId = interaction.id
                            self._lastUsage = interaction.usage
                            let output = interaction.outputText ?? ""
                            self._transcript.append(.assistantMessage(output))
                        }
                    } else {
                        let session = self.makeToolSession()
                        let configParams = self.buildConfigParams()
                        let modelStr = self.modelString()
                        for try await event in session.stream(
                            model: modelStr,
                            input: [User(message)],
                            configParams: configParams
                        ) {
                            continuation.yield(event)
                            // Update agent state from streaming events
                            switch event {
                            case .toolCallStarted(_, let name, let args):
                                self._transcript.append(.toolCall(name: name, arguments: args))
                            case .toolCallCompleted(_, let name, let output, let duration):
                                self._transcript.append(.toolResult(name: name, result: output, duration: duration))
                            case .llm(let llmEvent):
                                if case .interactionCompleted(let interaction) = llmEvent {
                                    self._lastInteractionId = interaction.id
                                    self._lastUsage = interaction.usage
                                    if interaction.isComplete {
                                        self._transcript.append(.assistantMessage(interaction.outputText ?? ""))
                                    }
                                }
                            default:
                                break
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    self._transcript.append(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Resets the agent's conversation state — clears the interaction chain, transcript, and usage.
    public func reset() {
        _lastInteractionId = nil
        _lastUsage = nil
        _transcript = []
    }

    // MARK: - Private helpers

    private func sendDirect(message: String) async throws -> Interaction {
        let request = buildDirectRequest(message: message)
        return try await client.send(request)
    }

    private func sendWithTools(message: String) async throws -> Interaction {
        let session = makeToolSession()
        let result = try await session.run(
            model: modelString(),
            input: [User(message)],
            configParams: buildConfigParams()
        )
        for entry in result.log {
            _transcript.append(.toolCall(name: entry.name, arguments: entry.arguments))
            _transcript.append(.toolResult(name: entry.name, result: entry.result, duration: entry.duration))
        }
        _lastInteractionId = result.interaction.id
        _lastUsage = result.totalUsage
        return result.interaction
    }

    private func buildDirectRequest(message: String) -> InteractionRequest {
        var request = InteractionRequest(input: .text(message))
        applyModelIdentifier(to: &request)
        request.systemInstruction = instructions
        // Apply caller config params first (they may set previousInteractionId, store, etc.)
        for param in configParams {
            param.apply(to: &request)
        }
        // Re-enforce chaining state: previousInteractionId and store must be set after configParams
        // so that user-provided params cannot accidentally clear them.
        if let id = _lastInteractionId {
            request.previousInteractionId = id
            request.store = true
        }
        return request
    }

    /// A private config param that routes named-agent requests correctly:
    /// clears `model` and sets `agent` so ToolSession sends the right JSON field.
    private struct AgentIdentifierParam: InteractionConfigParameter, Sendable {
        let name: String
        func apply(to request: inout InteractionRequest) {
            request.agent = name
            request.model = nil
        }
    }

    private func buildConfigParams() -> [any InteractionConfigParameter] {
        var params = configParams
        // When using a named agent with ToolSession, override model → agent
        if case .agent(let name) = modelIdentifier {
            params.append(AgentIdentifierParam(name: name))
        }
        if let id = _lastInteractionId {
            params.append(PreviousInteractionId(id))
            params.append(Store(true))
        }
        if let instr = instructions {
            params.append(SystemInstruction(instr))
        }
        return params
    }

    private func makeToolSession() -> ToolSession {
        var handlers: [String: ToolSession.ToolHandler] = [:]
        for tool in agentTools {
            if case .function(let name, _, _) = tool.tool {
                handlers[name] = tool.handler
            }
        }
        return ToolSession(
            client: client,
            tools: agentTools.map { $0.tool },
            handlers: handlers,
            maxIterations: maxToolIterations
        )
    }

    private func applyModelIdentifier(to request: inout InteractionRequest) {
        switch modelIdentifier {
        case .model(let m):
            request.model = m
        case .agent(let a):
            request.agent = a
            // Explicitly ensure model is nil when using named agent
            request.model = nil
        }
    }

    private func modelString() -> String {
        switch modelIdentifier {
        case .model(let m): return m
        case .agent(let a): return a
        }
    }

    private static func validateToolNames(_ tools: [AgentTool]) throws {
        var seen = Set<String>()
        for tool in tools {
            if case .function(let name, _, _) = tool.tool {
                if !seen.insert(name).inserted {
                    throw GeminiInteractionsError.invalidInput("Duplicate tool name: '\(name)'")
                }
            }
        }
    }
}

#endif
