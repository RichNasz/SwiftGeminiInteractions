// Sources/SwiftGeminiInteractions/Agent.swift
import Foundation

// MARK: - AgentTool

public struct AgentTool: Sendable {
    public let tool: InteractionTool
    public let handler: ToolSession.ToolHandler

    public init(tool: InteractionTool, handler: @escaping ToolSession.ToolHandler) {
        self.tool = tool
        self.handler = handler
    }

    /// Convenience init for `LLMTool`-conforming types.
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

public enum TranscriptEntry: Sendable {
    case userMessage(String)
    case assistantMessage(String)
    case thought(String)
    case toolCall(name: String, arguments: String)
    case toolResult(name: String, result: String, duration: Duration)
    case builtInToolCall(type: String)
    case error(String)
}

// MARK: - Agent

private enum ModelIdentifier: Sendable {
    case model(String)
    case agent(String)
}

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

    public var lastInteractionId: String? { _lastInteractionId }
    public var lastUsage: Usage? { _lastUsage }
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

    /// Send a message and return the model's output text.
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

    /// Stream events from the model, yielding `ToolSessionEvent` values.
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

    /// Reset conversation state: clears last interaction ID and transcript.
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

    private func buildConfigParams() -> [any InteractionConfigParameter] {
        var params = configParams
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
